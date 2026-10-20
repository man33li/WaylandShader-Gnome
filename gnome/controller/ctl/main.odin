package ctl

// waylandshader-gnomectl: state machine of src/ctl_main.cpp:142-287 on a GMainLoop.

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:encoding/json"
import "core:fmt"
import "core:os"

import "../../common"
import "../client"

foreign import glib "system:glib-2.0"

@(default_calling_convention = "c")
foreign glib {
	g_log :: proc(domain: cstring, level: c.uint, format: cstring, #c_vararg args: ..any) ---
	g_main_loop_new :: proc(ctx: rawptr, is_running: b32) -> rawptr ---
	g_main_loop_run :: proc(loop: rawptr) ---
	g_main_loop_quit :: proc(loop: rawptr) ---
	g_main_loop_unref :: proc(loop: rawptr) ---
	g_timeout_add :: proc(interval: c.uint, function: proc "c" (data: rawptr) -> b32, data: rawptr) -> c.uint ---
	g_idle_add :: proc(function: proc "c" (data: rawptr) -> b32, data: rawptr) -> c.uint ---
	g_source_remove :: proc(tag: c.uint) -> b32 ---
}

App :: struct {
	cmd:              Command,
	loop:             rawptr,
	cl:               client.Client,
	deadline:         c.uint,
	exit_code:        int,
	finished:         bool,
	load_accepted:    bool,
	load_in_progress: bool,
}

// §5.6: log CRITICAL without allocating, then trap, for assertion failures inside C callbacks.
boundary_failure :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	g_log(nil, 1 << 3, "%.*s: %.*s", c.int(len(prefix)), raw_data(prefix), c.int(len(message)), raw_data(message))
	runtime.trap()
}

boundary_context :: proc "contextless" () -> runtime.Context {
	result := runtime.default_context()
	result.assertion_failure_proc = boundary_failure
	return result
}

main :: proc() {
	cmd, usage_error, exit := parse(os.args)
	if exit != 0 {
		fmt.eprint(usage_error)
		libc.exit(c.int(exit))
	}
	if cmd.help {
		fmt.print(help_text(cmd.argv0))
		libc.exit(0)
	}

	app, alloc_err := new(App)
	if alloc_err != nil {
		fmt.eprintln("Out of memory")
		libc.exit(3)
	}
	app.cmd = cmd
	app.loop = g_main_loop_new(nil, false)
	// A failed init leaves a safe Client: ensure_available then replies Unavailable (exit 3).
	_ = client.init(&app.cl)
	app.cl.listener = app
	app.cl.on_status = on_status
	app.cl.on_transport_error = on_transport_error
	g_idle_add(start, app)
	g_main_loop_run(app.loop)
	client.close(&app.cl)
	g_main_loop_unref(app.loop)
	libc.exit(c.int(app.exit_code))
}

// finish records the exit code once, stops the deadline and leaves the loop.
finish :: proc(app: ^App, code: int, message: string = "") {
	if app.finished {
		return
	}
	app.finished = true
	if app.deadline != 0 {
		g_source_remove(app.deadline)
		app.deadline = 0
	}
	if message != "" {
		fmt.eprintln(message)
	}
	app.exit_code = code
	g_main_loop_quit(app.loop)
}

fail :: proc(app: ^App, err: client.Error) {
	finish(app, 1 if err.kind == .Rejected else 3, err.message)
}

usage_exit :: proc(app: ^App, message: string) {
	// src/ctl_main.cpp:66-69 (written after the output of finish, as the original did)
	finish(app, 2, fmt.tprintf("%s\nUse %s --help for usage.", message, CLI_NAME))
}

print_value :: proc(app: ^App, value: json.Value) {
	text, err := common.stringify(value, true)
	if err != nil {
		finish(app, 3, fmt.tprint(err.?))
		return
	}
	fmt.print(text)
	delete(text) // stringify returns a heap string
}

print_status :: proc(app: ^App) {
	print_value(app, app.cl.status.json)
}

evaluate_load :: proc(app: ^App, status: ^client.Status) {
	if app.finished || !app.load_accepted {
		return
	}
	if status.loading {
		if status.requested_preset != app.cmd.preset {
			finish(app, 1, fmt.tprintf("Another preset load replaced this request: %s", status.requested_preset))
		}
		return
	}
	if status.error != "" {
		finish(app, 1, fmt.tprintf("Shader load failed: %s\nPreviously loaded preset: %s", status.error, status.preset))
	} else if status.preset != app.cmd.preset {
		finish(
			app,
			1,
			fmt.tprintf(
				"Loading ended without the requested preset becoming current. Current preset: %s",
				status.preset,
			),
		)
	} else {
		print_status(app)
		finish(app, 0)
	}
}

on_status :: proc(listener: rawptr, status: ^client.Status) {
	evaluate_load(cast(^App)listener, status)
}

on_transport_error :: proc(listener: rawptr, err: client.Error) {
	fail(cast(^App)listener, err)
}

on_deadline :: proc "c" (data: rawptr) -> b32 {
	context = boundary_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	app := cast(^App)data
	app.deadline = 0 // the source is removed by returning false
	if app.load_in_progress {
		finish(
			app,
			4,
			"Timed out waiting for shader loading. The request was not cancelled and may still finish; use status to check.",
		)
	} else {
		finish(
			app,
			4,
			fmt.tprintf(
				"Timed out waiting for %s. A mutation may still finish; use status to check.",
				client.COMPOSITOR,
			),
		)
	}
	return false
}

start :: proc "c" (data: rawptr) -> b32 {
	context = boundary_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	app := cast(^App)data
	app.deadline = g_timeout_add(c.uint(app.cmd.timeout * 1000), on_deadline, app)
	client.ensure_available(&app.cl, !read_only(app.cmd.kind), {on_available, app})
	return false
}

on_available :: proc(data: rawptr, err: client.Error) {
	app := cast(^App)data
	if app.finished {
		return
	}
	if err.kind != .None {
		fail(app, err)
		return
	}
	cmd := &app.cmd
	if read_only(cmd.kind) {
		if cmd.kind == .Status {
			print_status(app)
		} else {
			// QJsonValue::toArray() of a missing or non-array value is an empty array
			array, is_array := app.cl.status.json[cmd.name].(json.Array)
			print_value(app, is_array ? array : json.Array{})
		}
		finish(app, 0)
		return
	}
	if cmd.kind == .Load {
		app.load_in_progress = true
		client.load_preset(&app.cl, cmd.preset, {on_load_accepted, app})
		return
	}
	reply := client.Reply{on_mutation_done, app}
	#partial switch cmd.kind {
	case .Param:
		client.set_parameter(&app.cl, cmd.param_name, cmd.value, reply)
	case .Output:
		id, resolved := select_output(app.cl.status.outputs, cmd.selector, app)
		if !resolved {
			return
		}
		switch cmd.action {
		case .Shader:
			client.set_output_shader_enabled(&app.cl, id, cmd.enabled, reply)
		case .Color:
			client.set_output_color_enabled(&app.cl, id, cmd.enabled, reply)
		case .Gamma:
			client.set_output_gamma(&app.cl, id, cmd.value, reply)
		case .Saturation:
			client.set_output_saturation(&app.cl, id, cmd.value, reply)
		}
	case:
		enabled := cmd.kind == .Enable || (cmd.kind == .Toggle && !app.cl.status.enabled)
		client.set_enabled(&app.cl, enabled, reply)
	}
}

// Exact id first, then a unique exact name (src/ctl_main.cpp:249-272).
select_output :: proc(outputs: []client.Output, selector: string, app: ^App) -> (id: string, ok: bool) {
	for output in outputs {
		if output.id == selector {
			return output.id, true
		}
	}
	found := false
	for output in outputs {
		if output.name != selector {
			continue
		}
		if found {
			usage_exit(app, fmt.tprintf("Ambiguous monitor name: %s. Use a monitor id from outputs instead.", selector))
			return "", false
		}
		id, found = output.id, true
	}
	if !found {
		usage_exit(app, fmt.tprintf("Unknown monitor id or name: %s", selector))
	}
	return id, found
}

on_load_accepted :: proc(data: rawptr, err: client.Error) {
	app := cast(^App)data
	if app.finished {
		return
	}
	if err.kind != .None {
		fail(app, err)
		return
	}
	// A status signal may arrive before the acceptance reply: query again rather than
	// interpreting pre-request state as completion.
	app.load_accepted = true
	client.request_status(&app.cl, {on_status_reply, app})
}

on_status_reply :: proc(data: rawptr, err: client.Error) {
	app := cast(^App)data
	if !app.finished && err.kind != .None {
		fail(app, err)
	}
}

on_mutation_done :: proc(data: rawptr, err: client.Error) {
	app := cast(^App)data
	if app.finished {
		return
	}
	if err.kind != .None {
		fail(app, err)
		return
	}
	client.request_status(&app.cl, {on_mutation_status, app})
}

on_mutation_status :: proc(data: rawptr, err: client.Error) {
	app := cast(^App)data
	if app.finished {
		return
	}
	if err.kind != .None {
		fail(app, err)
		return
	}
	print_status(app)
	finish(app, 0)
}
