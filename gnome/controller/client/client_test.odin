package client

import "core:fmt"
import "core:strings"
import "core:testing"
import json "core:encoding/json"
import glib "../../glib"

VALID :: `{"enabled":true,"active":false,"loading":false,"preset":"","requestedPreset":"","error":"","recentPresets":["/a.slangp"],"parameters":[{"name":"GAIN","description":"Gain","minimum":0,"maximum":2,"step":0.1,"default":1,"value":1}],"outputs":[{"id":"A","name":"Monitor","shaderEnabled":true,"colorEnabled":true,"shaderActive":false,"colorActive":false,"gamma":1,"saturation":1}]}`

@(test)
classification :: proc(t: ^testing.T) {
    for name in ([]string{"ServiceUnknown", "UnknownObject", "UnknownMethod", "UnknownInterface"}) {
        remote := fmt.tprintf("org.freedesktop.DBus.Error.%s", name)
        e := classify(remote, "message", false)
        testing.expect_value(t, e.kind, Kind.Unavailable)
        testing.expect_value(t, e.message, fmt.tprintf("%s: message%s", remote, INSTALLATION_HINT))
    }
    for name in ([]string{"org.waylandshader.Error.Unavailable", "org.waylandshader.Error.InvalidArgument"}) {
        testing.expect_value(t, classify(name, "message", false).kind, Kind.Rejected)
    }
    testing.expect_value(t, classify("org.freedesktop.DBus.Error.NoReply", "message", false).kind, Kind.Transport)
    testing.expect_value(t, classify("org.waylandshader.Error.InvalidArgument", "message", true).kind, Kind.Transport)
}

@(test)
local_errors :: proc(t: ^testing.T) {
    io := glib.g_io_error_quark()
    name, text := local_error(io, glib.IO_ERROR_TIMED_OUT, "Timeout was reached")
    testing.expect_value(t, name, "org.freedesktop.DBus.Error.NoReply")
    testing.expect(t, strings.has_prefix(text, "Did not receive a reply. Possible causes include:"))
    e := classify(name, text, true)
    testing.expect_value(t, e.kind, Kind.Transport)
    testing.expect(t, strings.has_prefix(e.message, "org.freedesktop.DBus.Error.NoReply: Did not receive a reply."))
    for code in ([]i32{glib.IO_ERROR_TIMED_OUT, glib.IO_ERROR_CLOSED}) {
        name, text = local_error(io, code, "gio text")
        testing.expect_value(t, name, "org.freedesktop.DBus.Error.NoReply")
        testing.expect_value(t, text, "Did not receive a reply. Possible causes include: the remote application did not send a reply, the message bus security policy blocked the reply, the reply timeout expired, or the network connection was broken.")
    }
    name, text = local_error(glib.g_quark_from_static_string("other"), glib.IO_ERROR_TIMED_OUT, "m")
    testing.expect_value(t, name, "org.freedesktop.DBus.Error.Failed")
    testing.expect_value(t, text, "m")
}

expect_invalid :: proc(t: ^testing.T, source, message: string) {
    c: Client
    if !testing.expect_value(t, accept_json(&c, VALID).kind, Kind.None) {
        free_status(&c.status)
        testing.fail_now(t, "Valid status prerequisite failed")
    }
    defer free_status(&c.status)
    original := c.status.json.value.(json.Object)
    e := accept_json(&c, source)
    if !testing.expect_value(t, e.kind, Kind.Protocol) {
        free_status(&c.status)
        testing.fail_now(t, "Invalid status was accepted")
    }
    testing.expect_value(t, e.message, fmt.tprintf("Invalid WaylandShader status: %s", message))
    testing.expect(t, c.has_status)
    testing.expect_value(t, c.status.parameters[0].name, "GAIN")
    // An invalid candidate never takes ownership of the old parsed object.
    testing.expect_value(t, c.status.json.value.(json.Object)["enabled"].(json.Boolean), original["enabled"].(json.Boolean))
}
replace_invalid :: proc(t: ^testing.T, old, new, message: string) {
    candidate, _ := strings.replace_all(VALID, old, new, context.temp_allocator)
    expect_invalid(t, candidate, message)
}

@(test)
status_validation :: proc(t: ^testing.T) {
    c: Client
    defer free_status(&c.status)
    if !testing.expect_value(t, accept_json(&c, VALID).kind, Kind.None) {
        free_status(&c.status)
        testing.fail_now(t, "Valid status prerequisite failed")
    }
    testing.expect_value(t, c.status.outputs[0].settings.gamma, f64(1))
    testing.expect_value(t, c.status.recent_presets[0], "/a.slangp")
    expect_invalid(t, "[]", "expected a JSON object: no error occurred")
    expect_invalid(t, "not json", "expected a JSON object: illegal value")
    expect_invalid(t, VALID + " false", "expected a JSON object: garbage at the end of the document")
    for field in ([]string{"enabled", "active", "loading"}) {
        old := fmt.tprintf(`"%s":%s`, field, field == "enabled" ? "true" : "false")
        replace_invalid(t, old, fmt.tprintf(`"%s":0`, field), fmt.tprintf("%s must be boolean.", field))
    }
    for field in ([]string{"preset", "requestedPreset", "error"}) {
        replace_invalid(t, fmt.tprintf(`"%s":""`, field), fmt.tprintf(`"%s":0`, field), fmt.tprintf("%s must be a string.", field))
    }
    replace_invalid(t, `"parameters":[{`, `"parameters":null,"unused":[{`, "parameters and outputs must be arrays.")
    replace_invalid(t, `"outputs":[{`, `"outputs":null,"unused":[{`, "parameters and outputs must be arrays.")
    replace_invalid(t, `"recentPresets":["/a.slangp"]`, `"recentPresets":0`, "recentPresets must be an array.")
    for value in ([]string{`[""]`, `[7]`}) {
        replace_invalid(t, `["/a.slangp"]`, value, "recent preset must be a nonempty string.")
    }
    replace_invalid(t, `"parameters":[{`, `"parameters":[0],"unused":[{`, "parameter must be an object.")
    for patch in ([][2]string{{`"name":"GAIN"`, `"name":""`}, {`"name":"GAIN"`, `"name":7`}, {`"description":"Gain"`, `"description":7`}}) {
        replace_invalid(t, patch[0], patch[1], "parameter name/description must be strings; name must not be empty.")
    }
    for field in ([]string{"minimum", "maximum", "step", "default", "value"}) {
        value := "1"
        if field == "minimum" { value = "0" }; if field == "maximum" { value = "2" }; if field == "step" { value = "0.1" }
        replace_invalid(t, fmt.tprintf(`"%s":%s`, field, value), fmt.tprintf(`"%s":null`, field), fmt.tprintf("parameter %s must be finite numeric data.", field))
    }
    for patch in ([][2]string{{`"minimum":0`, `"minimum":3`}, {`"step":0.1`, `"step":-1`}, {`"value":1`, `"value":3`}, {`"value":1`, `"value":-1`}, {`"default":1`, `"default":3`}, {`"default":1`, `"default":-1`}}) {
        replace_invalid(t, patch[0], patch[1], "duplicate parameter or invalid bounds: GAIN")
    }
    parameter := `{"name":"GAIN","description":"Gain","minimum":0,"maximum":2,"step":0.1,"default":1,"value":1}`
    replace_invalid(t, parameter, fmt.tprintf("%s,%s", parameter, parameter), "duplicate parameter or invalid bounds: GAIN")
    replace_invalid(t, `"outputs":[{`, `"outputs":[0],"unused":[{`, "output must be an object.")
    for patch in ([][2]string{{`"id":"A"`, `"id":""`}, {`"id":"A"`, `"id":7`}, {`"name":"Monitor"`, `"name":7`}}) {
        replace_invalid(t, patch[0], patch[1], "output id/name must be strings; id must not be empty.")
    }
    for field in ([]string{"shaderEnabled", "colorEnabled", "shaderActive", "colorActive"}) {
        value := strings.has_suffix(field, "Enabled") ? "true" : "false"
        replace_invalid(t, fmt.tprintf(`"%s":%s`, field, value), fmt.tprintf(`"%s":0`, field), fmt.tprintf("output %s must be boolean.", field))
    }
    for field in ([]string{"gamma", "saturation"}) {
        replace_invalid(t, fmt.tprintf(`"%s":1`, field), fmt.tprintf(`"%s":null`, field), fmt.tprintf("output %s must be finite numeric data.", field))
    }
    replace_invalid(t, `"gamma":1`, `"bypass":7,"gamma":1`, "output bypass must be a string.")
    for patch in ([][2]string{{`"gamma":1`, `"gamma":0.09`}, {`"gamma":1`, `"gamma":5.01`}, {`"saturation":1`, `"saturation":-1`}, {`"saturation":1`, `"saturation":2.01`}}) {
        replace_invalid(t, patch[0], patch[1], "duplicate output id or invalid bounds: A")
    }
    output := `{"id":"A","name":"Monitor","shaderEnabled":true,"colorEnabled":true,"shaderActive":false,"colorActive":false,"gamma":1,"saturation":1}`
    replace_invalid(t, output, fmt.tprintf("%s,%s", output, output), "duplicate output id or invalid bounds: A")
    absent, allocated := strings.replace_all(VALID, `"recentPresets":["/a.slangp"],`, "")
    defer if allocated { delete(absent) }
    testing.expect_value(t, accept_json(&c, absent).kind, Kind.None)
    with_bypass, allocated_bypass := strings.replace_all(VALID, `"gamma":1`, `"bypass":"inactive","gamma":1`)
    defer if allocated_bypass { delete(with_bypass) }
    testing.expect_value(t, accept_json(&c, with_bypass).kind, Kind.None)
    testing.expect_value(t, c.status.outputs[0].bypass, "inactive")
}

Reply_Result :: struct { calls: int, kind: Kind }
record_reply :: proc(data: rawptr, error: Error) {
    result := cast(^Reply_Result)data
    result.calls += 1
    result.kind = error.kind
}

@(test)
boolean_and_closed_client :: proc(t: ^testing.T) {
    testing.expect_value(t, boolean_reply(nil).kind, Kind.Protocol)
    for accepted in ([2]b32{false, true}) {
        reply := glib.g_variant_new("(b)", accepted)
        e := boolean_reply(reply)
        testing.expect_value(t, e.kind, accepted ? Kind.None : Kind.Rejected)
        glib.g_variant_unref(reply)
    }
    wrong := glib.g_variant_new("(s)", cstring("true"))
    testing.expect_value(t, boolean_reply(wrong).message, "GNOME Shell returned a malformed boolean reply.")
    glib.g_variant_unref(wrong)
    c: Client
    result: Reply_Result
    r := Reply{record_reply, &result}
    ensure_available(&c, true, r)
    request_status(&c, r)
    set_enabled(&c, true, r)
    load_preset(&c, "/missing.slangp", r)
    set_parameter(&c, "GAIN", 1, r)
    set_output_shader_enabled(&c, "A", true, r)
    set_output_color_enabled(&c, "A", true, r)
    set_output_gamma(&c, "A", 1, r)
    set_output_saturation(&c, "A", 1, r)
    testing.expect_value(t, result.calls, 9)
    testing.expect_value(t, result.kind, Kind.Unavailable)
    close(&c)
    close(&c)
    set_parameter(&c, "bad\x00name", 1, r)
    testing.expect_value(t, result.kind, Kind.Protocol)
    set_parameter(&c, "\xff", 1, r)
    testing.expect_value(t, result.kind, Kind.Protocol)
}

@(test)
json_depth_limit :: proc(t: ^testing.T) {
    opening := strings.repeat("[", 1025, context.temp_allocator)
    closing := strings.repeat("]", 1025, context.temp_allocator)
    expect_invalid(t, fmt.tprintf("%s0%s", opening, closing), "expected a JSON object: too deeply nested document")
}

@(test)
json_compatibility :: proc(t: ^testing.T) {
    for row in ([][2]string{
        {"{", "unterminated object"},
        {"[", "unterminated array"},
        {"\v{}", "illegal number"},
        {"\f{}", "illegal number"},
        {`{"a" 0}`, "missing name separator"},
        {`{"a":0 "b":1}`, "unterminated object"},
        {`{"a":0,}`, "object is missing after a comma"},
        {`{"a":"unterminated}`, "unterminated string"},
    }) {
        expect_invalid(t, row[0], fmt.tprintf("expected a JSON object: %s", row[1]))
    }
    c: Client
    defer free_status(&c.status)
    duplicate, _ := strings.replace_all(VALID, `"enabled":true`, `"enabled":false,"enabled":true,"":7`, context.temp_allocator)
    if !testing.expect_value(t, accept_json(&c, duplicate).kind, Kind.None) {
        free_status(&c.status)
        testing.fail_now(t, "Duplicate-key status prerequisite failed")
    }
    testing.expect(t, c.status.enabled)
    testing.expect_value(t, c.status.json.value.(json.Object)[""].(json.Float), f64(7))
    escaped, _ := strings.replace_all(VALID, `"description":"Gain"`, `"description":"G\qain"`, context.temp_allocator)
    if !testing.expect_value(t, accept_json(&c, escaped).kind, Kind.None) {
        free_status(&c.status)
        testing.fail_now(t, "Unknown-escape status prerequisite failed")
    }
    testing.expect_value(t, c.status.parameters[0].description, "Gqain")
}

@(test)
status_string_provenance :: proc(t: ^testing.T) {
    c: Client
    defer free_status(&c.status)
    for pair in ([][2]string{
        {"\xef\xbb\xbf", ""},
        {`\ufeff`, "\xef\xbb\xbf"},
        {"\xef\xbb\xbf\xef\xbb\xbf", "\xef\xbb\xbf"},
        {"\xef\xbb\xbf" + `\u0041`, "\xef\xbb\xbfA"},
    }) {
        source:=VALID
        for patch in ([][2]string{
            {`"preset":""`, fmt.tprintf(`"preset":"%s/p"`,pair[0])},
            {`"requestedPreset":""`, fmt.tprintf(`"requestedPreset":"%s/r"`,pair[0])},
            {`"error":""`, fmt.tprintf(`"error":"%sfailure"`,pair[0])},
            {`"/a.slangp"`, fmt.tprintf(`"%s/a.slangp"`,pair[0])},
            {`"name":"GAIN"`, fmt.tprintf(`"name":"%sGAIN"`,pair[0])},
            {`"description":"Gain"`, fmt.tprintf(`"description":"%sGain"`,pair[0])},
            {`"id":"A"`, fmt.tprintf(`"id":"%sA"`,pair[0])},
            {`"name":"Monitor"`, fmt.tprintf(`"name":"%sMonitor"`,pair[0])},
            {`"gamma":1`, fmt.tprintf(`"bypass":"%sinactive","gamma":1`,pair[0])},
        }) { source,_=strings.replace_all(source,patch[0],patch[1],context.temp_allocator) }
        if !testing.expect_value(t,accept_json(&c,source).kind,Kind.None) { continue }
        testing.expect_value(t,c.status.preset,fmt.tprintf("%s/p",pair[1]))
        testing.expect_value(t,c.status.requested_preset,fmt.tprintf("%s/r",pair[1]))
        testing.expect_value(t,c.status.error,fmt.tprintf("%sfailure",pair[1]))
        testing.expect_value(t,c.status.recent_presets[0],fmt.tprintf("%s/a.slangp",pair[1]))
        testing.expect_value(t,c.status.parameters[0].name,fmt.tprintf("%sGAIN",pair[1]))
        testing.expect_value(t,c.status.parameters[0].description,fmt.tprintf("%sGain",pair[1]))
        testing.expect_value(t,c.status.outputs[0].id,fmt.tprintf("%sA",pair[1]))
        testing.expect_value(t,c.status.outputs[0].name,fmt.tprintf("%sMonitor",pair[1]))
        testing.expect_value(t,c.status.outputs[0].bypass,fmt.tprintf("%sinactive",pair[1]))
    }
    replace_invalid(t,`"name":"GAIN"`,"\"name\":\"\xef\xbb\xbf\"","parameter name/description must be strings; name must not be empty.")
    replace_invalid(t,`"id":"A"`,"\"id\":\"\xef\xbb\xbf\"","output id/name must be strings; id must not be empty.")
    replace_invalid(t,`["/a.slangp"]`,"[\"\xef\xbb\xbf\"]","recent preset must be a nonempty string.")
    // D-Bus QString decoding and JSON document decoding are separate, single-BOM stages.
    testing.expect_value(t,accept_json(&c,"\xef\xbb\xbf\xef\xbb\xbf"+VALID).kind,Kind.None)
    expect_invalid(t,"\xef\xbb\xbf\xef\xbb\xbf\xef\xbb\xbf"+VALID,"expected a JSON object: illegal number")
}
