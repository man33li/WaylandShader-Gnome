package client

import "core:testing"
import glib "../../glib"

@(test)
profile_calls_on_closed_client :: proc(t: ^testing.T) {
    c: Client
    result: Reply_Result
    reply := Reply{record_reply, &result}
    request_profiles(&c, reply)
    save_profile(&c, " Movie ", reply)
    load_profile(&c, " Movie ", reply)
    load_profile_status(&c, " Movie ", reply)
    delete_profile(&c, " Movie ", reply)
    set_default_profile(&c, "", reply)
    testing.expect_value(t, result.calls, 6)
    testing.expect_value(t, result.kind, Kind.Unavailable)
}

@(test)
profile_status_reply_uses_owned_status_parser :: proc(t: ^testing.T) {
    c: Client
    defer free_status(&c.status)
    life := Life{client=&c}
    reply := glib.g_variant_new("(s)", cstring(VALID))
    testing.expect_value(t, status_reply(&life, reply).kind, Kind.None)
    glib.g_variant_unref(reply)
    testing.expect(t, c.has_status)
    testing.expect_value(t, c.status.parameters[0].name, "GAIN")
    wrong := glib.g_variant_new("(b)", b32(true))
    testing.expect_value(t, status_reply(&life, wrong).kind, Kind.Protocol)
    glib.g_variant_unref(wrong)
    testing.expect_value(t, c.status.parameters[0].name, "GAIN")
}
