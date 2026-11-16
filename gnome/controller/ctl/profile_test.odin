package ctl

import "core:testing"
import "../client"

@(test)
profile_acceptance_error_is_not_lost_to_a_later_status :: proc(t: ^testing.T) {
    app := App{cmd=Command{kind=.Profile, profile=.Load}}
    app.loop = g_main_loop_new(nil, false)
    defer g_main_loop_unref(app.loop)
    snapshot := `{"enabled":false,"active":false,"loading":false,"preset":"/previous.slangp","requestedPreset":"","error":"profile preset failed","parameters":[],"outputs":[]}`
    testing.expect_value(t, client.accept_json(&app.cl, snapshot).kind, client.Kind.None)
    defer client.free_status(&app.cl.status)
    on_load_accepted(&app, {})
    defer delete(app.cmd.preset)
    testing.expect(t, app.finished)
    testing.expect_value(t, app.exit_code, 1)
}

@(test)
profile_commands_and_exact_names :: proc(t: ^testing.T) {
    for action in ([]string{"save", "load", "delete", "default"}) {
        for name in ([]string{" Movie ", "__proto__", "constructor"}) {
            cmd, error, exit := run("profile", action, name)
            testing.expect_value(t, exit, 0)
            testing.expect_value(t, error, "")
            testing.expect_value(t, cmd.kind, Kind.Profile)
            testing.expect_value(t, cmd.profile_name, name)
        }
        _, _, exit := run("profile", action, "   ")
        testing.expect_value(t, exit, 2)
    }
    cmd, _, exit := run("profile", "clear-default")
    testing.expect_value(t, exit, 0)
    testing.expect_value(t, cmd.profile, Profile_Action.Clear_Default)
}

@(test)
profile_and_direct_load_target_identity :: proc(t: ^testing.T) {
    state := client.Status{loading=true, requested_preset="/movie.slangp", preset="/previous.slangp"}
    testing.expect(t, load_target_matches(&state, "/movie.slangp"))
    testing.expect(t, !load_target_matches(&state, "/replacement.slangp"))
    state.loading = false
    state.preset = "/replacement.slangp"
    testing.expect(t, !load_target_matches(&state, "/movie.slangp"))
    state.preset = "/movie.slangp"
    testing.expect(t, load_target_matches(&state, "/movie.slangp"))
    state.preset = ""
    testing.expect(t, load_target_matches(&state, ""))
}
