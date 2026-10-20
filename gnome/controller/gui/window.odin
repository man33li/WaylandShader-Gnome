package main

import "base:runtime"
import "core:c"
import "core:math"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import "core:testing"
import "../../common"
import "../client"

// ---------------------------------------------------------------------------
// Spin-button editors (design §4.6, spike S3)
// ---------------------------------------------------------------------------

// shortcut: GTK 3 ignores stepping increments ≤ 1e-10 (gtkspinbutton.c:1887); replace with an entry+buttons editor if such parameters must step
// Deviation D2. Typed and programmatic values stay exact: see param_input and spin_set.
new_parameter_spin :: proc(minimum, maximum, step, value: f64) -> Widget {
	adj := gtk_adjustment_new(value, minimum, maximum, step, step * 10, 0)
	spin := gtk_spin_button_new(adj, 0, 0)
	connect(spin, "input", param_input, nil)
	connect(spin, "output", param_output, nil)
	gtk_widget_set_hexpand(spin, true)
	// Re-emit "output" now that our handler is connected, so the initial text is the f32 text.
	gtk_spin_button_set_value(spin, gtk_adjustment_get_value(adj))
	return spin
}

// Gamma / saturation: the text commits as QDoubleSpinBox(2 decimals) would send it.
connect_round2_spin :: proc(spin: Widget) {
	connect(spin, "input", round2_input, nil)
}

// The adjustment compares exactly, so unlike gtk_spin_button_set_value it never
// drops changes below GTK's 1e-10 EPSILON; its value-changed also refreshes the text.
spin_set :: proc(spin: Widget, value: f64) {
	gtk_adjustment_set_value(gtk_spin_button_get_adjustment(spin), value)
}

// [A4]: set the adjustment before returning so the typed f32 is committed exactly.
param_input :: proc "c" (spin: Widget, new_value: ^f64, _: rawptr) -> c.int {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	value, ok := parse_f32(string(gtk_entry_get_text(spin)))
	if !ok {
		return GTK_INPUT_ERROR
	}
	gtk_adjustment_set_value(gtk_spin_button_get_adjustment(spin), f64(value))
	new_value^ = f64(value)
	return 1
}

param_output :: proc "c" (spin: Widget, _: rawptr) -> b32 {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	adj := gtk_spin_button_get_adjustment(spin)
	gtk_entry_set_text(spin, cstr(format_f32(gtk_adjustment_get_value(adj))))
	return true
}

round2_input :: proc "c" (spin: Widget, new_value: ^f64, _: rawptr) -> c.int {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	value, ok := strconv.parse_f64(strings.trim_space(string(gtk_entry_get_text(spin))))
	if !ok || math.is_nan(value) || math.is_inf(value) {
		return GTK_INPUT_ERROR
	}
	new_value^ = round2(value)
	return 1
}

// S3 self-check. Compiled in always but inert unless built with
// -define:WS_GTK_SPIN_SELFCHECK=true, because GtkSpinButton needs a GDK display
// (use xvfb-run): with the define set, a missing display fails the test.
WS_GTK_SPIN_SELFCHECK :: #config(WS_GTK_SPIN_SELFCHECK, false)

@(test)
spin_commit_selfcheck :: proc(t: ^testing.T) {
	if !WS_GTK_SPIN_SELFCHECK {
		return
	}
	if !gtk_init_check(nil, nil) {
		testing.fail_now(t, "no GDK display: run under xvfb-run or a desktop session")
	}
	// Tiny f32 typed into a tiny-range parameter commits exactly.
	spin := new_parameter_spin(0, 1e-6, 1e-8, 0)
	gtk_entry_set_text(spin, "1.0000001e-7")
	gtk_spin_button_update(spin)
	testing.expect_value(t, gtk_spin_button_get_value(spin), f64(f32(1.0000001e-7)))
	// Smallest subnormal f32, with a step below GTK's EPSILON (D2 affects stepping only).
	spin = new_parameter_spin(0, 1e-6, 1e-12, 0)
	gtk_entry_set_text(spin, "1.4e-45")
	gtk_spin_button_update(spin)
	testing.expect_value(t, gtk_spin_button_get_value(spin), f64(f32(1.4e-45)))
	// Programmatic sets below EPSILON are exact too.
	spin_set(spin, 3e-12)
	testing.expect_value(t, gtk_spin_button_get_value(spin), 3e-12)

	// Gamma 1.234 commits as 1.23 (and 1.236 as 1.24).
	gamma := gtk_spin_button_new(
		gtk_adjustment_new(1, common.MIN_GAMMA, common.MAX_GAMMA, 0.05, 0.5, 0), 0, 2)
	connect_round2_spin(gamma)
	gtk_entry_set_text(gamma, "1.234")
	gtk_spin_button_update(gamma)
	testing.expect_value(t, gtk_spin_button_get_value(gamma), round2(1.234))
	testing.expect(t, abs(gtk_spin_button_get_value(gamma) - 1.23) < 1e-12)
	gtk_entry_set_text(gamma, "1.236")
	gtk_spin_button_update(gamma)
	testing.expect(t, abs(gtk_spin_button_get_value(gamma) - 1.24) < 1e-12)
}

// ---------------------------------------------------------------------------
// Window state (GUI:221-589). One window per process, so the state is a global.
// ---------------------------------------------------------------------------

Editor :: struct {
	name, description:                      string, // heap
	minimum, maximum, step, default_value: f64,
	spin:                                   Widget,
	timer:                                  c.uint, // GLib source id, 0 = none
	dirty:                                  bool,
	revision:                               u64,
	index:                                  int,
}

Output_Item :: struct {
	id, name: string, // heap
}

// Lifetime record of one in-flight set_parameter call; freed by its reply.
Param_Reply :: struct {
	epoch:    u64,
	index:    int,
	revision: u64,
}

Output_Kind :: enum {
	Shader,
	Color,
	Gamma,
	Saturation,
}

PARAMETER_DEBOUNCE_MS :: 100

App :: struct {
	cl:                                                 client.Client,
	win, preset, recent, recent_menu, load, enabled:    Widget,
	output, output_state, output_shader, output_color:  Widget,
	gamma, saturation, summary, error, parameters:      Widget,
	editors:                                            [dynamic]^Editor,
	output_items:                                       [dynamic]Output_Item,
	recent_presets:                                     [dynamic]cstring,
	pending_params:                                     [dynamic]^Param_Reply, // in-flight records; freed by the reply or at close
	parameter_preset, operation_error:                  string,
	selected_output_id, pending_output_id:              string,
	form_rows:                                          int,
	epoch:                                              u64, // bumped by every editor rebuild; stale replies are ignored
	programmatic:                                       int, // >0 while code (not the user) changes widgets: QSignalBlocker
	available, loading, load_pending, enable_pending:   bool,
	path_edited, output_pending, closing:               bool,
}

app: App

sensitive :: proc(w: Widget, s: bool) {
	gtk_widget_set_sensitive(w, b32(s))
}

load_enabled :: proc() -> bool {
	return app.available && !app.loading && !app.load_pending
}

set_available :: proc(available: bool) {
	app.available = available
	sensitive(app.load, load_enabled())
	sensitive(app.enabled, available && !app.enable_pending)
	sensitive(app.parameters, available && !app.loading)
	update_output_availability()
}

selected_output :: proc() -> ^client.Output {
	for &o in app.cl.status.outputs {
		if o.id == app.selected_output_id {
			return &o
		}
	}
	return nil
}

update_output_availability :: proc() {
	idle := app.available && !app.output_pending
	sensitive(app.output, idle && len(app.output_items) > 0)
	editable := idle && selected_output() != nil
	sensitive(app.output_shader, editable)
	sensitive(app.output_color, editable)
	sensitive(app.gamma, editable)
	sensitive(app.saturation, editable)
}

// Focus loss can commit spin-box text. Discard any remaining edit before
// rebinding the controls, especially when hotplug removes the old monitor.
select_output :: proc(id: string) {
	if id == app.selected_output_id {
		return
	}
	app.programmatic += 1
	defer app.programmatic -= 1
	if gtk_widget_has_focus(app.gamma) || gtk_widget_has_focus(app.saturation) {
		gtk_window_set_focus(app.win, nil)
	}
	set_str(&app.selected_output_id, id)
	output := selected_output()
	spin_set(app.gamma, output != nil ? round2(output.settings.gamma) : 1.0)
	spin_set(app.saturation, output != nil ? round2(output.settings.saturation) : 1.0)
	gtk_widget_set_tooltip_text(app.output, cstr(id))
}

update_output_controls :: proc() {
	app.programmatic += 1
	defer app.programmatic -= 1
	output := selected_output()
	pending := app.output_pending && app.pending_output_id == app.selected_output_id
	if !pending {
		settings := output != nil ? output.settings : common.DEFAULT_OUTPUT_SETTINGS
		gtk_toggle_button_set_active(app.output_shader, b32(output != nil && settings.shader_enabled))
		gtk_toggle_button_set_active(app.output_color, b32(output != nil && settings.color_enabled))
		if !gtk_widget_has_focus(app.gamma) {
			spin_set(app.gamma, round2(settings.gamma))
		}
		if !gtk_widget_has_focus(app.saturation) {
			spin_set(app.saturation, round2(settings.saturation))
		}
	}
	gtk_label_set_text(app.output_state, cstr(state_label(output, pending, app.cl.status.enabled)))
	update_output_availability()
}

update_outputs :: proc(status: ^client.Status) {
	changed := len(app.output_items) != len(status.outputs)
	for i := 0; !changed && i < len(app.output_items); i += 1 {
		changed = app.output_items[i].id != status.outputs[i].id || app.output_items[i].name != status.outputs[i].name
	}
	app.programmatic += 1
	if changed {
		for item in app.output_items {
			delete(item.id)
			delete(item.name)
		}
		clear(&app.output_items)
		gtk_combo_box_text_remove_all(app.output)
		for &o in status.outputs {
			id, id_err := strings.clone(o.id)
			name, name_err := strings.clone(o.name)
			if id_err != nil || name_err != nil {
				g_log(nil, G_LOG_LEVEL_WARNING, "Out of memory")
				continue
			}
			append(&app.output_items, Output_Item{id, name})
			gtk_combo_box_text_append(app.output, cstr(id), cstr(name))
		}
		if len(app.output_items) == 0 {
			gtk_combo_box_text_append(app.output, nil, "No connected monitors")
		}
	}
	index := -1
	for item, i in app.output_items {
		if item.id == app.selected_output_id {
			index = i
		}
	}
	if index < 0 && len(app.output_items) > 0 {
		index = 0
	}
	gtk_combo_box_set_active(app.output, c.int(max(index, 0))) // index 0 is the placeholder when there are no outputs
	app.programmatic -= 1
	select_output(index >= 0 ? app.output_items[index].id : "")
	update_output_controls()
}

// Returns the stable id captured at commit time; the controls stay disabled until
// the post-mutation status has reconciled the values.
begin_output :: proc() -> (id: string, ok: bool) {
	if app.programmatic > 0 || !app.available || app.output_pending || selected_output() == nil {
		return
	}
	id = app.selected_output_id
	app.output_pending = true
	set_str(&app.pending_output_id, id)
	clear_str(&app.operation_error)
	update_output_controls()
	show_errors()
	return id, true
}

change_output :: proc(kind: Output_Kind, value: f64) {
	id, ok := begin_output()
	if !ok {
		return
	}
	reply := client.Reply{fn = output_mutation_done}
	switch kind {
	case .Shader:
		client.set_output_shader_enabled(&app.cl, id, value != 0, reply)
	case .Color:
		client.set_output_color_enabled(&app.cl, id, value != 0, reply)
	case .Gamma:
		client.set_output_gamma(&app.cl, id, value, reply)
	case .Saturation:
		client.set_output_saturation(&app.cl, id, value, reply)
	}
}

show_errors :: proc() {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, app.operation_error)
	if app.cl.has_status && len(app.cl.status.error) > 0 {
		if strings.builder_len(b) > 0 {
			strings.write_byte(&b, '\n')
		}
		strings.write_string(&b, "Effect error: ")
		strings.write_string(&b, app.cl.status.error)
	}
	gtk_label_set_text(app.error, cstr(strings.to_string(b)))
	gtk_widget_set_visible(app.error, b32(strings.builder_len(b) > 0))
}

set_operation_error :: proc(message: string) {
	set_str(&app.operation_error, message)
}

reconnect :: proc() {
	set_available(false)
	clear_str(&app.operation_error)
	client.ensure_available(&app.cl, true, client.Reply{fn = reconnect_done})
}

reconnect_done :: proc(_: rawptr, err: client.Error) {
	if app.closing {
		return
	}
	if err.kind != .None {
		set_operation_error(err.message)
		gtk_label_set_text(app.summary, "WaylandShader is unavailable.")
		set_available(false)
	} else {
		set_available(true)
	}
	show_errors()
}

finish_mutation :: proc(err: client.Error, output_mutation := false) {
	if err.kind != .None {
		set_operation_error(err.message)
		if err.kind != .Rejected {
			set_available(false)
		}
	}
	show_errors()
	client.request_status(&app.cl, client.Reply{fn = output_mutation ? output_status_done : plain_status_done})
}

output_mutation_done :: proc(_: rawptr, err: client.Error) {
	if !app.closing {
		finish_mutation(err, true)
	}
}

enable_done :: proc(_: rawptr, err: client.Error) {
	if app.closing {
		return
	}
	app.enable_pending = false
	finish_mutation(err)
}

load_done :: proc(_: rawptr, err: client.Error) {
	if app.closing {
		return
	}
	app.load_pending = false
	finish_mutation(err)
}

status_done :: proc(err: client.Error, output_mutation: bool) {
	if app.closing {
		return
	}
	if output_mutation {
		app.output_pending = false
		clear_str(&app.pending_output_id)
	}
	if err.kind != .None {
		set_operation_error(err.message)
		set_available(false)
		show_errors()
	}
	if output_mutation {
		update_output_controls()
	}
}

plain_status_done :: proc(_: rawptr, err: client.Error) {
	status_done(err, false)
}

output_status_done :: proc(_: rawptr, err: client.Error) {
	status_done(err, true)
}

do_load :: proc() {
	entry := gtk_entry_get_text(app.preset) // NUL-terminated already: no conversion needed
	text := string(entry)
	message := load_error(text)
	canonical: cstring
	if len(message) == 0 {
		canonical = posix.realpath(entry)
		if canonical == nil {
			message = "Choose an existing .slangp preset file."
		}
	}
	if len(message) > 0 {
		set_operation_error(message)
		show_errors()
		return
	}
	defer posix.free(rawptr(canonical))
	clear_str(&app.operation_error)
	app.load_pending = true
	set_available(app.available)
	client.load_preset(&app.cl, string(canonical), client.Reply{fn = load_done})
}

do_browse :: proc() {
	dialog := gtk_file_chooser_dialog_new(
		"Choose shader preset",
		app.win,
		GTK_FILE_CHOOSER_ACTION_OPEN,
		cstring("_Cancel"),
		c.int(GTK_RESPONSE_CANCEL),
		cstring("_Open"),
		c.int(GTK_RESPONSE_ACCEPT),
		rawptr(nil),
	)
	if dialog == nil {
		return
	}
	defer gtk_widget_destroy(dialog)
	filter := gtk_file_filter_new()
	gtk_file_filter_set_name(filter, "RetroArch slang presets (*.slangp)")
	gtk_file_filter_add_pattern(filter, "*.slangp")
	gtk_file_chooser_add_filter(dialog, filter)
	// The chooser starts at the entry text: a directory is opened, a file is selected,
	// and a not-yet-existing file starts in its parent directory.
	entry := gtk_entry_get_text(app.preset)
	text := string(entry)
	if len(text) > 0 {
		st: posix.stat_t
		if posix.stat(entry, &st) == .OK {
			if posix.S_ISDIR(st.st_mode) {
				gtk_file_chooser_set_current_folder(dialog, entry)
			} else {
				gtk_file_chooser_set_filename(dialog, entry)
			}
		} else if slash := strings.last_index_byte(text, '/'); slash > 0 {
			// On allocation failure the chooser simply starts at its default location.
			if parent, ok := cstr_try(text[:slash]); ok {
				if posix.stat(parent, &st) == .OK && posix.S_ISDIR(st.st_mode) {
					gtk_file_chooser_set_current_folder(dialog, parent)
				}
			}
		}
	}
	if gtk_dialog_run(dialog) != GTK_RESPONSE_ACCEPT {
		return
	}
	if path := gtk_file_chooser_get_filename(dialog); path != nil {
		gtk_entry_set_text(app.preset, path)
		app.path_edited = true
		g_free(rawptr(path))
	}
}

// ---------------------------------------------------------------------------
// Parameter editors
// ---------------------------------------------------------------------------

destroy_children :: proc(container: Widget) {
	list := gtk_container_get_children(container)
	for node := list; node != nil; node = node.next {
		gtk_widget_destroy(node.data)
	}
	g_list_free(list)
}

// Removes every timer first: a timer must never fire for a freed editor.
clear_editors :: proc() {
	for e in app.editors {
		if e.timer != 0 {
			g_source_remove(e.timer)
		}
		delete(e.name)
		delete(e.description)
		free(e)
	}
	clear(&app.editors)
}

find_editor :: proc(name: string) -> ^Editor {
	for e in app.editors {
		if e.name == name {
			return e
		}
	}
	return nil
}

same_parameters :: proc(status: ^client.Status) -> bool {
	if app.form_rows == 0 {
		return false
	}
	if len(app.editors) != len(status.parameters) || app.parameter_preset != status.preset {
		return false
	}
	for &p in status.parameters {
		e := find_editor(p.name)
		if e == nil ||
		   e.description != p.description ||
		   e.minimum != p.minimum ||
		   e.maximum != p.maximum ||
		   e.step != p.step ||
		   e.default_value != p.default_value {
			return false
		}
	}
	return true
}

build_parameters :: proc(status: ^client.Status) {
	app.epoch += 1
	clear_editors()
	destroy_children(app.parameters)
	set_str(&app.parameter_preset, status.preset)
	row: c.int
	for &p in status.parameters {
		e, e_err := new(Editor)
		if e_err != nil {
			g_log(nil, G_LOG_LEVEL_WARNING, "Out of memory")
			continue
		}
		name, name_err := strings.clone(p.name)
		description, description_err := strings.clone(p.description)
		if name_err != nil || description_err != nil {
			g_log(nil, G_LOG_LEVEL_WARNING, "Out of memory")
			if name_err == nil {
				delete(name)
			}
			if description_err == nil {
				delete(description)
			}
			free(e)
			continue
		}
		e^ = Editor {
			name          = name,
			description   = description,
			minimum       = p.minimum,
			maximum       = p.maximum,
			step          = p.step,
			default_value = p.default_value,
			index         = len(app.editors),
		}
		e.spin = new_parameter_spin(p.minimum, p.maximum, parameter_step(&p), p.value)
		gtk_widget_set_tooltip_text(e.spin, cstr(parameter_tooltip(&p)))
		connect(e.spin, "value-changed", editor_changed, e)
		connect(e.spin, "activate", refresh_status_soon, nil)
		connect(e.spin, "focus-out-event", refresh_status_on_focus_out, nil)
		label := gtk_label_new(cstr(parameter_label(&p)))
		gtk_label_set_xalign(label, 0)
		gtk_label_set_line_wrap(label, true)
		gtk_label_set_max_width_chars(label, 40)
		gtk_label_set_mnemonic_widget(label, e.spin)
		gtk_grid_attach(app.parameters, label, 0, row, 1, 1)
		gtk_grid_attach(app.parameters, e.spin, 1, row, 1, 1)
		append(&app.editors, e)
		row += 1
	}
	if len(status.parameters) == 0 {
		text: cstring = "Load a preset to see its declared parameters."
		if len(status.preset) > 0 {
			text = "This preset declares no adjustable parameters."
		}
		label := gtk_label_new(text)
		gtk_label_set_xalign(label, 0)
		gtk_grid_attach(app.parameters, label, 0, 0, 2, 1)
		row = 1
	}
	app.form_rows = int(row)
	gtk_widget_show_all(app.parameters)
}

restart_timer :: proc(e: ^Editor) {
	if e.timer != 0 {
		g_source_remove(e.timer)
	}
	e.timer = g_timeout_add(PARAMETER_DEBOUNCE_MS, parameter_timer, e)
}

param_done :: proc(data: rawptr, err: client.Error) {
	r := (^Param_Reply)(data)
	reply := r^
	for p, i in app.pending_params {
		if p == r {
			unordered_remove(&app.pending_params, i)
			break
		}
	}
	free(r)
	// GUI:477-479: a reply for a rebuilt (destroyed) editor does nothing at all.
	if app.closing || reply.epoch != app.epoch || reply.index >= len(app.editors) {
		return
	}
	if e := app.editors[reply.index]; e.revision == reply.revision {
		e.dirty = false
	}
	finish_mutation(err)
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

update_recent_presets :: proc(presets: []string) {
	same := len(presets) == len(app.recent_presets)
	for i := 0; same && i < len(presets); i += 1 {
		same = presets[i] == string(app.recent_presets[i])
	}
	if same {
		return
	}
	destroy_children(app.recent_menu)
	for p in app.recent_presets {
		delete(p)
	}
	clear(&app.recent_presets)
	for p in presets {
		cp, err := strings.clone_to_cstring(p)
		if err != nil {
			g_log(nil, G_LOG_LEVEL_WARNING, "Out of memory")
			continue
		}
		append(&app.recent_presets, cp)
		// A plain label item: the path is never parsed for mnemonics.
		item := gtk_menu_item_new_with_label(cp)
		connect(item, "activate", recent_activate, rawptr(cp))
		gtk_menu_shell_append(app.recent_menu, item)
		gtk_widget_show(item)
	}
	sensitive(app.recent, len(presets) > 0)
}

update_status :: proc(status: ^client.Status) {
	app.loading = status.loading
	set_available(true)
	if !app.enable_pending {
		app.programmatic += 1
		gtk_toggle_button_set_active(app.enabled, b32(status.enabled))
		app.programmatic -= 1
	}
	update_recent_presets(status.recent_presets)
	if !app.path_edited && !gtk_widget_has_focus(app.preset) {
		app.programmatic += 1
		gtk_entry_set_text(app.preset, cstr(status.loading ? status.requested_preset : status.preset))
		app.programmatic -= 1
	}
	update_outputs(status)
	gtk_label_set_text(app.summary, cstr(summary_text(status)))
	if !same_parameters(status) {
		build_parameters(status)
	}
	app.programmatic += 1
	for &p in status.parameters {
		if e := find_editor(p.name); e != nil && !e.dirty && !gtk_widget_has_focus(e.spin) {
			spin_set(e.spin, p.value)
		}
	}
	app.programmatic -= 1
	show_errors()
}

on_status :: proc(_: rawptr, status: ^client.Status) {
	if !app.closing {
		update_status(status)
	}
}

on_transport_error :: proc(_: rawptr, err: client.Error) {
	if app.closing {
		return
	}
	set_available(false)
	set_operation_error(err.message)
	show_errors()
	gtk_label_set_text(app.summary, "Disconnected — displayed controls may be stale. Use Reconnect / refresh.")
}

// ---------------------------------------------------------------------------
// GTK callbacks: every one is a C entry (design §5.6)
// ---------------------------------------------------------------------------

// editingFinished: refresh only after focus moved; the callback never submits an edit.
refresh_status_idle :: proc "c" (_: rawptr) -> b32 {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if !app.closing && app.cl.has_status {
		update_status(&app.cl.status)
	}
	return false
}

refresh_outputs_idle :: proc "c" (_: rawptr) -> b32 {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if !app.closing {
		update_output_controls()
	}
	return false
}

startup_idle :: proc "c" (_: rawptr) -> b32 {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if !app.closing {
		reconnect()
	}
	return false
}

refresh_status_soon :: proc "c" (_: Widget, _: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	g_idle_add(refresh_status_idle, nil)
}

refresh_status_on_focus_out :: proc "c" (_: Widget, _: rawptr, _: rawptr) -> b32 {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	g_idle_add(refresh_status_idle, nil)
	return false
}

refresh_outputs_soon :: proc "c" (_: Widget, _: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	g_idle_add(refresh_outputs_idle, nil)
}

refresh_outputs_on_focus_out :: proc "c" (_: Widget, _: rawptr, _: rawptr) -> b32 {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	g_idle_add(refresh_outputs_idle, nil)
	return false
}

parameter_timer :: proc "c" (data: rawptr) -> b32 {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	e := (^Editor)(data)
	e.timer = 0
	if app.closing {
		return false
	}
	r, err := new(Param_Reply)
	if err != nil {
		g_log(nil, G_LOG_LEVEL_WARNING, "Out of memory")
		return false
	}
	r^ = Param_Reply{epoch = app.epoch, index = e.index, revision = e.revision}
	if _, append_err := append(&app.pending_params, r); append_err != nil {
		g_log(nil, G_LOG_LEVEL_WARNING, "Out of memory")
		free(r)
		return false
	}
	clear_str(&app.operation_error)
	client.set_parameter(&app.cl, e.name, gtk_spin_button_get_value(e.spin), client.Reply{fn = param_done, data = r})
	return false
}

editor_changed :: proc "c" (_: Widget, data: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if app.programmatic > 0 {
		return
	}
	e := (^Editor)(data)
	e.dirty = true
	e.revision += 1
	restart_timer(e)
}

recent_activate :: proc "c" (_: Widget, data: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	gtk_entry_set_text(app.preset, cstring(data))
	app.path_edited = true
	gtk_widget_grab_focus(app.preset)
}

preset_changed :: proc "c" (_: Widget, _: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if app.programmatic == 0 {
		app.path_edited = true // textEdited: user edits only
	}
}

preset_activate :: proc "c" (_: Widget, _: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if load_enabled() {
		do_load()
	}
}

browse_clicked :: proc "c" (_: Widget, _: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	do_browse()
}

load_clicked :: proc "c" (_: Widget, _: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	do_load()
}

reconnect_clicked :: proc "c" (_: Widget, _: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	reconnect()
}

enabled_toggled :: proc "c" (button: Widget, _: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if app.programmatic > 0 {
		return
	}
	app.enable_pending = true
	sensitive(app.enabled, false)
	clear_str(&app.operation_error)
	client.set_enabled(&app.cl, bool(gtk_toggle_button_get_active(button)), client.Reply{fn = enable_done})
}

output_changed :: proc "c" (combo: Widget, _: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if app.programmatic > 0 {
		return
	}
	id := gtk_combo_box_get_active_id(combo)
	select_output(id != nil ? string(id) : "")
	update_output_controls()
}

output_toggled :: proc "c" (button: Widget, data: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	change_output(Output_Kind(uintptr(data)), gtk_toggle_button_get_active(button) ? 1 : 0)
}

output_spin_changed :: proc "c" (spin: Widget, data: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	// Arrow steps bypass the input handler, so round here too (QDoubleSpinBox, 2 decimals).
	change_output(Output_Kind(uintptr(data)), round2(gtk_spin_button_get_value(spin)))
}

window_destroyed :: proc "c" (_: Widget, _: rawptr) {
	context = gui_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	app.closing = true
	for r in app.pending_params { // close() suppresses their replies, so free them here
		free(r)
	}
	clear(&app.pending_params)
	clear_editors()
	client.close(&app.cl)
	gtk_main_quit()
}

// ---------------------------------------------------------------------------
// Construction (GUI:67-219)
// ---------------------------------------------------------------------------

lookup :: proc(b: Builder, name: cstring, ok: ^bool) -> Widget {
	w := gtk_builder_get_object(b, name)
	if w == nil {
		g_log(nil, G_LOG_LEVEL_CRITICAL, "controller.ui has no object %s", name)
		ok^ = false
	}
	return w
}

build_window :: proc(ui: string) -> bool {
	b := gtk_builder_new()
	err: ^GError
	if gtk_builder_add_from_string(b, raw_data(ui), c.size_t(len(ui)), &err) == 0 {
		g_log(nil, G_LOG_LEVEL_CRITICAL, "controller.ui: %s", err != nil ? err.message : "unknown error")
		if err != nil {
			g_error_free(err)
		}
		g_object_unref(b)
		return false
	}
	ok := true
	app.win = lookup(b, "window", &ok)
	app.preset = lookup(b, "preset", &ok)
	app.recent = lookup(b, "recent", &ok)
	app.load = lookup(b, "load", &ok)
	app.enabled = lookup(b, "enabled", &ok)
	app.output = lookup(b, "output", &ok)
	app.output_state = lookup(b, "output_state", &ok)
	app.output_shader = lookup(b, "output_shader", &ok)
	app.output_color = lookup(b, "output_color", &ok)
	app.gamma = lookup(b, "gamma", &ok)
	app.saturation = lookup(b, "saturation", &ok)
	app.summary = lookup(b, "summary", &ok)
	app.error = lookup(b, "error", &ok)
	app.parameters = lookup(b, "parameters", &ok)
	browse := lookup(b, "browse", &ok)
	reconnect_button := lookup(b, "reconnect", &ok)
	g_object_unref(b) // the window keeps itself alive until gtk_widget_destroy
	if !ok {
		if app.win != nil {
			gtk_widget_destroy(app.win)
		}
		return false
	}

	app.recent_menu = gtk_menu_new()
	gtk_menu_button_set_popup(app.recent, app.recent_menu)
	gtk_spin_button_set_range(app.gamma, common.MIN_GAMMA, common.MAX_GAMMA)
	gtk_spin_button_set_range(app.saturation, common.MIN_SATURATION, common.MAX_SATURATION)
	spin_set(app.gamma, 1.0)
	spin_set(app.saturation, 1.0)
	connect_round2_spin(app.gamma)
	connect_round2_spin(app.saturation)
	set_available(false)

	connect(browse, "clicked", browse_clicked, nil)
	connect(app.preset, "changed", preset_changed, nil)
	connect(app.preset, "activate", preset_activate, nil)
	connect(app.load, "clicked", load_clicked, nil)
	connect(reconnect_button, "clicked", reconnect_clicked, nil)
	connect(app.enabled, "toggled", enabled_toggled, nil)
	connect(app.output, "changed", output_changed, nil)
	connect(app.output_shader, "toggled", output_toggled, rawptr(uintptr(Output_Kind.Shader)))
	connect(app.output_color, "toggled", output_toggled, rawptr(uintptr(Output_Kind.Color)))
	connect(app.gamma, "value-changed", output_spin_changed, rawptr(uintptr(Output_Kind.Gamma)))
	connect(app.saturation, "value-changed", output_spin_changed, rawptr(uintptr(Output_Kind.Saturation)))
	for spin in ([2]Widget{app.gamma, app.saturation}) {
		connect(spin, "activate", refresh_outputs_soon, nil)
		connect(spin, "focus-out-event", refresh_outputs_on_focus_out, nil)
	}
	connect(app.win, "destroy", window_destroyed, nil)

	// Baseline (CC:64,119): no bus never aborts; every call then reports Unavailable
	// ("Cannot connect to the session D-Bus…") and the window shows the disconnected state.
	if !client.init(&app.cl) {
		g_log(nil, G_LOG_LEVEL_WARNING, "Cannot connect to the session D-Bus")
	}
	app.cl.on_status = on_status
	app.cl.on_transport_error = on_transport_error
	return true
}
