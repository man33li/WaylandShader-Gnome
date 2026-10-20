package client

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:strings"
import glib "../../glib"

SERVICE :: "org.gnome.Shell"
EFFECT_PATH :: "/WaylandShader"
EFFECT_INTERFACE :: "org.waylandshader.Effect"
ACTIVATION_PATH :: "/org/gnome/Shell"
ACTIVATION_INTERFACE :: "org.gnome.Shell.Extensions"
UUID :: "waylandshader@man33li.github.com"
COMPOSITOR :: "GNOME Shell"
DESKTOP_ENVIRONMENT :: "GNOME Shell / Mutter"
EFFECT_DESCRIPTION :: "WaylandShader GNOME extension"
INSTALLATION_HINT :: " Install the WaylandShader GNOME extension and its native module built for this GNOME Shell version, and allow user extensions. On NixOS, a new login may be required. GNOME Shell will not be restarted."
ACTIVATION_HINT :: "Mutation commands may enable only the waylandshader@man33li.github.com GNOME extension."
Kind :: enum { None, Unavailable, Rejected, Protocol, Transport }
Error :: struct { kind: Kind, message: string }
Reply :: struct { fn: proc(data: rawptr, err: Error), data: rawptr }
Client :: struct {
    status: Status, has_status: bool,
    listener: rawptr, on_status: proc(rawptr, ^Status), on_transport_error: proc(rawptr, Error),
    life: ^Life,
}
Life :: struct { client: ^Client, bus: ^glib.DBus_Connection, cancel: ^glib.Cancellable, refs: int, generation: u64, subscriptions: [3]u32, activations: ^Activation }
Operation :: enum { Status, Activated_Status, Mutation, Ensure, Enable, Snapshot }
Pending :: struct { life: ^Life, generation: u64, op: Operation, allow_activation: bool, reply: Reply, activation: ^Activation }
Activation :: struct { life: ^Life, next: ^Activation, reply: Reply, timer: u32, refs: int, done: bool }

boundary_failure :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
    glib.g_log(nil, 1<<3, "%.*s: %.*s", i32(len(prefix)), raw_data(prefix), i32(len(message)), raw_data(message))
    runtime.trap()
}
boundary_context :: proc "contextless" () -> runtime.Context {
    result := runtime.default_context()
    result.assertion_failure_proc = boundary_failure
    return result
}
respond :: proc(r: Reply, e: Error) { if r.fn != nil { r.fn(r.data, e) } }
classify :: proc(remote_name, message: string, local: bool) -> Error {
    kind := Kind.Transport
    if !local {
        switch remote_name {
        case "org.freedesktop.DBus.Error.ServiceUnknown", "org.freedesktop.DBus.Error.UnknownObject", "org.freedesktop.DBus.Error.UnknownMethod", "org.freedesktop.DBus.Error.UnknownInterface": kind = .Unavailable
        case: if strings.has_prefix(remote_name, "org.waylandshader.Error.") { kind = .Rejected }
        }
    }
    suffix := ""
    if kind == .Unavailable { suffix = INSTALLATION_HINT }
    return {kind, fmt.tprintf("%s: %s%s", remote_name, message, suffix)}
}
// Async GIO failures without a remote name. libdbus completes both a call timeout and a connection
// loss with the same synthesized NoReply (dbus-pending-call.c:390-395, dbus-connection.c:2302-2320,4251),
// which QDBusError reports verbatim; "Failed" is QDBusError's generic name (qdbuserror.cpp:26).
NO_REPLY :: "org.freedesktop.DBus.Error.NoReply"
NO_REPLY_TEXT :: "Did not receive a reply. Possible causes include: the remote application did not send a reply, the message bus security policy blocked the reply, the reply timeout expired, or the network connection was broken."
local_error :: proc(domain: u32, code: i32, message: string) -> (name, text: string) {
    if domain == glib.g_io_error_quark() && (code == glib.IO_ERROR_TIMED_OUT || code == glib.IO_ERROR_CLOSED) { return NO_REPLY, NO_REPLY_TEXT }
    return "org.freedesktop.DBus.Error.Failed", message
}

release :: proc(l: ^Life) { l.refs -= 1; if l.refs == 0 { glib.g_object_unref(l.cancel); glib.g_object_unref(l.bus); free(l) } }
activation_release :: proc(a: ^Activation) { a.refs -= 1; if a.refs == 0 { release(a.life); free(a) } }
transport :: proc(l: ^Life, e: Error) {
    c := l.client
    if c == nil { return }
    c.has_status = false
    if c.on_transport_error != nil { c.on_transport_error(c.listener, e) }
}
init :: proc(c: ^Client) -> bool {
    if c.life != nil { return true }
    l, allocation_error := new(Life)
    if allocation_error != nil { return false }
    error: ^glib.Error
    l.bus = glib.g_bus_get_sync(2, nil, &error)
    if error != nil { glib.g_error_free(error) }
    if l.bus == nil { free(l); return false }
    l.cancel = glib.g_cancellable_new()
    l.client, l.refs = c, 1
    c.life = l
    l.subscriptions[0] = glib.g_dbus_connection_signal_subscribe(l.bus, SERVICE, EFFECT_INTERFACE, "statusChanged", EFFECT_PATH, nil, 0, status_signal, l, nil)
    l.subscriptions[1] = glib.g_dbus_connection_signal_subscribe(l.bus, SERVICE, ACTIVATION_INTERFACE, "ExtensionStateChanged", ACTIVATION_PATH, UUID, 0, extension_signal, l, nil)
    l.subscriptions[2] = glib.g_dbus_connection_signal_subscribe(l.bus, "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus", SERVICE, 0, owner_signal, l, nil)
    for id in l.subscriptions { if id == 0 { close(c); return false } }
    return true
}
close :: proc(c: ^Client) {
    l := c.life
    if l == nil { return }
    c.life = nil
    l.client = nil
    glib.g_cancellable_cancel(l.cancel)
    for id in l.subscriptions { if id != 0 { glib.g_dbus_connection_signal_unsubscribe(l.bus, id) } }
    for l.activations != nil { activation_complete(l.activations, {}) }
    free_status(&c.status)
    c.has_status = false
    release(l)
}
call :: proc(l: ^Life, method: cstring, args: ^glib.Variant, op: Operation, r: Reply, allow := false, activation: ^Activation = nil) {
    p, allocation_error := new(Pending)
    if allocation_error != nil {
        if args != nil { glib.g_variant_unref(args) }
        if activation != nil { activation_complete(activation, {.Transport, "Out of memory"}) }
        else { respond(r, {.Transport, "Out of memory"}) }
        return
    }
    p^ = {life=l, generation=l.generation, op=op, reply=r, allow_activation=allow, activation=activation}
    l.refs += 1
    if activation != nil { activation.refs += 1 }
    path, iface := cstring(EFFECT_PATH), cstring(EFFECT_INTERFACE)
    if op == .Enable || op == .Snapshot { path, iface = ACTIVATION_PATH, ACTIVATION_INTERFACE }
    glib.g_dbus_connection_call(l.bus, SERVICE, path, iface, method, args, nil, 0, 10000, l.cancel, finished, p)
}
unavailable :: proc() -> Error { return {.Unavailable, "Cannot connect to the session D-Bus or subscribe to WaylandShader status."} }
request_status :: proc(c: ^Client, r: Reply) { if c.life == nil { respond(r, unavailable()); return }; call(c.life, "status", nil, .Status, r) }
ensure_available :: proc(c: ^Client, allow_activation: bool, r: Reply) { if c.life == nil { respond(r, unavailable()); return }; call(c.life, "status", nil, .Ensure, r, allow_activation) }
mutation :: proc(c: ^Client, method: cstring, args: ^glib.Variant, r: Reply) {
    if c.life == nil { glib.g_variant_unref(args); respond(r, unavailable()); return }
    call(c.life, method, args, .Mutation, r)
}
text_mutation :: proc(c: ^Client, method, format: cstring, text: string, r: Reply, enabled := false, value: f64 = 0) {
    arg, allocation_error := strings.clone_to_cstring(text)
    if allocation_error != nil { respond(r, {.Transport, "Out of memory"}); return }
    defer delete(arg)
    if !bool(glib.g_utf8_validate(arg, len(text), nil)) {
        respond(r, {.Protocol, "Invalid UTF-8 argument"})
        return
    }
    args: ^glib.Variant
    switch string(format) {
    case "(s)": args = glib.g_variant_new(format, arg)
    case "(sb)": args = glib.g_variant_new(format, arg, b32(enabled))
    case "(sd)": args = glib.g_variant_new(format, arg, value)
    }
    mutation(c, method, args, r)
}
load_preset :: proc(c: ^Client, path: string, r: Reply) { text_mutation(c, "loadPreset", "(s)", path, r) }
set_enabled :: proc(c: ^Client, enabled: bool, r: Reply) { mutation(c, "setEnabled", glib.g_variant_new("(b)", b32(enabled)), r) }
set_parameter :: proc(c: ^Client, name: string, value: f64, r: Reply) { text_mutation(c, "setParameter", "(sd)", name, r, value=value) }
set_output_shader_enabled :: proc(c: ^Client, id: string, value: bool, r: Reply) { text_mutation(c, "setOutputShaderEnabled", "(sb)", id, r, enabled=value) }
set_output_color_enabled :: proc(c: ^Client, id: string, value: bool, r: Reply) { text_mutation(c, "setOutputColorEnabled", "(sb)", id, r, enabled=value) }
set_output_gamma :: proc(c: ^Client, id: string, value: f64, r: Reply) { text_mutation(c, "setOutputGamma", "(sd)", id, r, value=value) }
set_output_saturation :: proc(c: ^Client, id: string, value: f64, r: Reply) { text_mutation(c, "setOutputSaturation", "(sd)", id, r, value=value) }
type_is :: proc(v: ^glib.Variant, signature: string) -> bool { return v != nil && string(glib.g_variant_get_type_string(v)) == signature }
boolean_reply :: proc(v: ^glib.Variant) -> Error {
    if !type_is(v, "(b)") { return {.Protocol, "GNOME Shell returned a malformed boolean reply."} }
    child := glib.g_variant_get_child_value(v, 0); defer glib.g_variant_unref(child)
    if !bool(glib.g_variant_get_boolean(child)) { return {.Rejected, "GNOME Shell rejected the request (returned false)."} }
    return {}
}
status_reply :: proc(l: ^Life, v: ^glib.Variant) -> Error {
    if !type_is(v, "(s)") { return {.Protocol, "GNOME Shell returned a malformed status reply (expected JSON string)."} }
    child := glib.g_variant_get_child_value(v, 0); defer glib.g_variant_unref(child)
    return accept_json(l.client, string(glib.g_variant_get_string(child, nil)))
}
finished :: proc "c" (source: rawptr, result: ^glib.Async_Result, data: rawptr) {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    p := cast(^Pending)data
    l := p.life
    defer { if p.activation != nil { activation_release(p.activation) }; release(l); free(p) }
    error: ^glib.Error
    value := glib.g_dbus_connection_call_finish(l.bus, result, &error)
    defer { if value != nil { glib.g_variant_unref(value) }; if error != nil { glib.g_error_free(error) } }
    if l.client == nil { return }
    e: Error
    remote := ""
    missing := false
    if error != nil {
        name := glib.g_dbus_error_get_remote_error(error)
        if name != nil { remote = string(name) }
        glib.g_dbus_error_strip_remote_error(error)
        text := string(error.message)
        if name == nil { remote, text = local_error(error.domain, error.code, text) }
        e = classify(remote, text, name == nil)
        missing = remote == "org.freedesktop.DBus.Error.UnknownObject" || remote == "org.freedesktop.DBus.Error.UnknownMethod" || remote == "org.freedesktop.DBus.Error.UnknownInterface"
        if name != nil { glib.g_free(rawptr(name)) }
    }
    if p.op != .Enable && p.op != .Snapshot && p.generation != l.generation {
        e = classify("org.freedesktop.DBus.Error.UnknownObject", "The WaylandShader control interface changed during the request. Reconnect to continue.", false)
    }
    if e.kind == .Unavailable && p.op != .Enable && p.op != .Snapshot {
        had_status := l.client.has_status
        l.client.has_status = false
        if had_status { transport(l, e); if l.client == nil { return } }
    }
    switch p.op {
    case .Status, .Activated_Status:
        if e.kind == .None { e = status_reply(l, value) }
        if p.op == .Activated_Status && e.kind != .None {
            e.message = fmt.tprintf("The effect was requested but its control interface is unavailable: %s", e.message)
        }
        if l.client != nil { respond(p.reply, e) }
    case .Mutation: if e.kind == .None { e = boolean_reply(value) }; respond(p.reply, e)
    case .Ensure:
        if !missing { if e.kind == .None { e = status_reply(l, value) }; if l.client != nil { respond(p.reply, e) }; return }
        if !p.allow_activation { respond(p.reply, {.Unavailable, "The WaylandShader GNOME extension is not available." + INSTALLATION_HINT + " Use the settings window or a mutation command to activate it."}); return }
        call(l, "EnableExtension", glib.g_variant_new("(s)", cstring(UUID)), .Enable, p.reply)
    case .Enable:
        if e.kind == .None { e = boolean_reply(value) }
        if e.kind != .None {
            suffix := ""; if e.kind != .Unavailable { suffix = INSTALLATION_HINT }
            if e.kind == .Rejected { e.kind = .Unavailable }
            e.message = fmt.tprintf("Could not activate the WaylandShader GNOME extension: %s%s", e.message, suffix)
            respond(p.reply, e); return
        }
        a, allocation_error := new(Activation)
        if allocation_error != nil { respond(p.reply, {.Transport, "Out of memory"}); return }
        a^ = {life=l, next=l.activations, reply=p.reply, refs=1}
        l.refs += 1
        l.activations = a
        a.timer = glib.g_timeout_add(10000, activation_timeout, a)
        call(l, "GetExtensionInfo", glib.g_variant_new("(s)", cstring(UUID)), .Snapshot, {}, activation=a)
    case .Snapshot:
        a := p.activation
        if a.done { return }
        if e.kind != .None { activation_complete(a, e); return }
        if !type_is(value, "(a{sv})") { activation_complete(a, {.Protocol, "GNOME Shell returned malformed extension information."}); return }
        info := glib.g_variant_get_child_value(value, 0); defer glib.g_variant_unref(info)
        inspect_activation(a, info)
    }
}
activation_complete :: proc(a: ^Activation, e: Error) {
    if a.done { return }
    a.done = true
    l := a.life
    link := &l.activations
    for link^ != nil { if link^ == a { link^ = a.next; break }; link = &link^.next }
    if a.timer != 0 { glib.g_source_remove(a.timer); a.timer = 0 }
    r := a.reply
    defer activation_release(a)
    if l.client == nil { return }
    if e.kind != .None {
        respond(r, {e.kind, fmt.tprintf("The effect was requested but its control interface is unavailable: %s", e.message)})
    } else { call(l, "status", nil, .Activated_Status, r) }
}
activation_timeout :: proc "c" (data: rawptr) -> b32 {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    a := cast(^Activation)data
    a.timer = 0
    activation_complete(a, {.Unavailable, "Timed out waiting for the WaylandShader GNOME extension to activate." + INSTALLATION_HINT})
    return false
}
state_value :: proc(info: ^glib.Variant) -> (u32, bool) {
    v := glib.g_variant_lookup_value(info, "state", nil)
    if v == nil { return 0, false }
    defer glib.g_variant_unref(v)
    if type_is(v, "u") { return glib.g_variant_get_uint32(v), true }
    if type_is(v, "i") { return u32(glib.g_variant_get_int32(v)), true }
    if type_is(v, "d") {
        value := glib.g_variant_get_double(v)
        if math.is_nan(value) || math.is_inf(value) || value < -0.5 || value >= 4294967295.5 { return 0, false }
        return u32(math.floor(value+0.5)), true
    }
    return 0, false
}
inspect_activation :: proc(a: ^Activation, info: ^glib.Variant) {
    state, valid := state_value(info)
    if !valid { activation_complete(a, {.Protocol, "GNOME Shell returned extension information without a valid state."}); return }
    if state == 1 { activation_complete(a, {}); return }
    if state == 2 || state == 6 || state == 8 { return }
    message := ""
    error := glib.g_variant_lookup_value(info, "error", nil)
    if error != nil { if type_is(error, "s") { message = string(glib.g_variant_get_string(error, nil)) }; defer glib.g_variant_unref(error) }
    activation_complete(a, {.Unavailable, fmt.tprintf("The WaylandShader GNOME extension could not become active (state %d): %s%s", state, message, INSTALLATION_HINT)})
}
status_signal :: proc "c" (connection: ^glib.DBus_Connection, sender, path, iface, signal: cstring, parameters: ^glib.Variant, data: rawptr) {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    l := cast(^Life)data
    l.refs += 1; defer release(l)
    if l.client == nil { return }
    e := status_reply(l, parameters)
    if e.kind != .None { transport(l, e) }
}
extension_signal :: proc "c" (connection: ^glib.DBus_Connection, sender, path, iface, signal: cstring, parameters: ^glib.Variant, data: rawptr) {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    l := cast(^Life)data
    l.refs += 1; defer release(l)
    if l.client == nil || !type_is(parameters, "(sa{sv})") { return }
    uuid := glib.g_variant_get_child_value(parameters, 0); defer glib.g_variant_unref(uuid)
    if string(glib.g_variant_get_string(uuid, nil)) != UUID { return }
    info := glib.g_variant_get_child_value(parameters, 1); defer glib.g_variant_unref(info)
    state := glib.g_variant_lookup_value(info, "state", nil)
    if state == nil { return }; glib.g_variant_unref(state)
    // Completion may remove the current activation or close the whole client.
    a := l.activations
    if a != nil { a.refs += 1 }
    for a != nil {
        next := a.next
        if next != nil { next.refs += 1 }
        if !a.done { inspect_activation(a, info) }
        activation_release(a)
        if l.client == nil { if next != nil { activation_release(next) }; return }
        a = next
    }
    number, _ := state_value(info)
    if number == 1 { return }
    l.generation += 1
    if l.client.has_status { transport(l, {.Unavailable, "The WaylandShader GNOME extension was disabled or became unavailable. Use Reconnect / refresh to activate it." + INSTALLATION_HINT}) }
}
owner_signal :: proc "c" (connection: ^glib.DBus_Connection, sender, path, iface, signal: cstring, parameters: ^glib.Variant, data: rawptr) {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    l := cast(^Life)data
    l.refs += 1; defer release(l)
    if l.client == nil || !type_is(parameters, "(sss)") { return }
    old := glib.g_variant_get_child_value(parameters, 1); defer glib.g_variant_unref(old)
    new := glib.g_variant_get_child_value(parameters, 2); defer glib.g_variant_unref(new)
    old_name := string(glib.g_variant_get_string(old, nil))
    if old_name != "" && old_name != string(glib.g_variant_get_string(new, nil)) {
        l.generation += 1
        transport(l, {.Unavailable, "The GNOME Shell D-Bus service disappeared or restarted. Reconnect to continue." + INSTALLATION_HINT})
    }
}
