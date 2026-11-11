package main

import "core:fmt"
import "core:os"
import glib "../glib"

Error :: Maybe(string)
Texture :: glib.Object
Framebuffer :: glib.Object
Pipeline :: glib.Object
Color_State :: glib.Object
Cogl_Context :: glib.Object
Luminance :: struct { kind: u32, minimum, maximum, reference, mastering_max: f32 }
Failure :: enum { none, working, pipeline1, blend1, pipeline2, blend2, snippet, gamma, saturation }
failure: Failure
pipeline_calls, blend_calls, snippet_calls: int
luminances: [256]Luminance
attached: [256]bool
transforms: [256]struct { source, target: ^Color_State, flags: u32 }
mock_error := glib.Error{message="Injected blending failure"}

reset :: proc() { glib.reset(); failure=.none; pipeline_calls=0; blend_calls=0; snippet_calls=0; luminances={}; attached={}; transforms={} }
color :: proc(ctx: rawptr, hdr: bool = false, parametric: bool = true) -> ^Color_State {
    p := glib.make(1 if parametric else 2,ctx)
    luminances[p.id] = {minimum=0, maximum=100, reference=100, mastering_max=1000 if hdr else 100}
    return p
}
clutter_color_state_params_get_type :: proc() -> glib.GType { return 1 }
clutter_color_state_params_get_luminance :: proc(p: ^Color_State) -> ^Luminance { assert(p != nil); return &luminances[p.id] }
clutter_color_state_params_new_full :: proc(ctx: rawptr, colorspace, transfer: u32, primaries: rawptr, gamma, minimum, maximum, reference, mastering_max: f32) -> ^Color_State {
    assert(ctx != nil && colorspace == 0 && transfer == 0 && primaries == nil && gamma == -1)
    if failure == .working { return nil }
    p := color(ctx)
    luminances[p.id] = {minimum=minimum, maximum=maximum, reference=reference, mastering_max=mastering_max}
    return p
}
clutter_color_state_equals :: proc(a,b: ^Color_State) -> b32 { return b32(a == b) }
clutter_color_state_add_pipeline_transform :: proc(a,b: ^Color_State, p: ^Pipeline, flags: u32) {
    assert(a.refs > 0 && b.refs > 0 && p.refs > 0)
    transforms[p.id] = {a,b,flags}
}
cogl_framebuffer_get_context :: proc(fb: ^Framebuffer) -> ^Cogl_Context { assert(fb != nil); return cast(^Cogl_Context)fb.ctx }
cogl_pipeline_new :: proc(ctx: ^Cogl_Context) -> ^Pipeline {
    pipeline_calls += 1
    if failure == .pipeline1 && pipeline_calls%2 == 1 || failure == .pipeline2 && pipeline_calls%2 == 0 { return nil }
    return glib.make(3,ctx)
}
cogl_pipeline_set_blend :: proc(p: ^Pipeline, expr: cstring, err: ^^glib.Error) -> bool {
    assert(string(expr) == "RGBA = ADD(SRC_COLOR, 0)")
    blend_calls += 1
    if failure == .blend1 && blend_calls%2 == 1 || failure == .blend2 && blend_calls%2 == 0 {
        err^ = &mock_error
        return false
    }
    return true
}
cogl_pipeline_set_layer_filters :: proc(p: ^Pipeline, layer: i32, min, mag: u32) { assert(layer == 0 && min == 9728 && mag == 9728) }
cogl_pipeline_set_layer_wrap_mode :: proc(p: ^Pipeline, layer: i32, mode: u32) { assert(layer == 0 && mode == 33071) }
cogl_snippet_new :: proc(hook: u32, declarations, body: cstring) -> rawptr {
    snippet_calls += 1
    assert(hook == 6145 && len(string(declarations)) > 0 && len(string(body)) > 0)
    if failure == .snippet { return nil }
    return glib.make(4)
}
cogl_pipeline_add_layer_snippet :: proc(p: ^Pipeline, layer: i32, snippet: rawptr) { assert(layer == 0 && snippet != nil); attached[p.id] = true }
cogl_pipeline_get_uniform_location :: proc(p: ^Pipeline, name: cstring) -> i32 {
    assert(attached[p.id])
    if string(name) == "wls_gamma" { return -1 if failure == .gamma else 10 }
    assert(string(name) == "wls_saturation")
    return -1 if failure == .saturation else 11
}

Inputs :: struct { cogl, clutter: ^glib.Object, target, srgb: ^Color_State, fb: ^Framebuffer }
inputs :: proc(hdr: bool = false) -> Inputs {
    reset()
    i := Inputs{cogl=glib.make(8),clutter=glib.make(9)}
    i.target=color(i.clutter,hdr); i.srgb=color(i.clutter); i.fb=glib.make(5,i.cogl)
    return i
}
finish :: proc(i: Inputs, r: ^Resources) {
    fixture_cleanup(r)
    glib.g_object_unref(i.target); glib.g_object_unref(i.srgb); glib.g_object_unref(i.fb)
    glib.g_object_unref(i.cogl); glib.g_object_unref(i.clutter)
    assert(glib.live_refs() == 0,"unbalanced constructor ownership")
}

snippet_failure_preserves_configuration :: proc() {
    i := inputs()
    r := Resources{raw={fb=i.fb},width=17,height=19}
    assert(configure_color(&r,i.target,i.srgb) == nil)
    r.gamma=2; r.saturation=3
    before := r; refs := glib.live_refs()
    other := color(i.clutter)
    failure=.snippet
    assert(configure_color(&r,other,i.srgb) != nil)
    assert(r == before,"failure published or discarded color configuration")
    assert(glib.live_refs() == refs+1,"candidate leaked references")
    glib.g_object_unref(other)
    finish(i,&r)
}
constructor_failures_are_atomic :: proc() {
    failures := [?]Failure{.working,.pipeline1,.blend1,.pipeline2,.blend2,.snippet,.gamma,.saturation}
    for good in ([?]bool{false,true}) {
        for f in failures {
            i := inputs(true)
            r := Resources{raw={fb=i.fb},width=17,height=19}
            if good { assert(configure_color(&r,i.target,i.srgb) == nil) }
            before := r
            other := color(i.clutter,true)
            refs := glib.live_refs()
            pipeline_calls=0; blend_calls=0; failure=f
            err := configure_color(&r,other,i.srgb)
            assert(err != nil,"constructor failure not returned")
            assert(r == before,"failed candidate altered published state")
            assert(glib.live_refs() == refs,"partial construction leaked/dropped refs")
            if f == .blend1 || f == .blend2 { assert(glib.error_frees == 1,"Cogl error ownership lost") }
            glib.g_object_unref(other)
            finish(i,&r)
        }
    }
}
failed_configuration_is_retried :: proc() {
    i := inputs()
    r := Resources{raw={fb=i.fb}}
    failure=.snippet
    assert(configure_color(&r,i.target,i.srgb) != nil)
    attempts := pipeline_calls
    failure=.none
    assert(configure_color(&r,i.target,i.srgb) == nil)
    assert(pipeline_calls > attempts,"retry falsely hit partial cache")
    assert(attached[r.to_target.id] && r.gamma_uniform == 10 && r.saturation_uniform == 11)
    finish(i,&r)
}
cache_uses_all_inputs :: proc() {
    i := inputs()
    r := Resources{raw={fb=i.fb}}
    assert(configure_color(&r,i.target,i.srgb) == nil)
    n := pipeline_calls
    assert(configure_color(&r,i.target,i.srgb) == nil && pipeline_calls == n,"unchanged configuration rebuilt")
    other_source := color(i.clutter)
    assert(configure_color(&r,i.target,other_source) == nil)
    assert(pipeline_calls == n+2 && r.working_color == other_source,"working-state input omitted from cache key")
    other_ctx := glib.make(8)
    i.fb.ctx=other_ctx
    n=pipeline_calls
    assert(configure_color(&r,i.target,other_source) == nil)
    assert(pipeline_calls == n+2 && r.to_srgb.ctx == other_ctx && r.to_target.ctx == other_ctx,"Cogl context omitted from cache key")
    n=pipeline_calls
    other_target := color(i.clutter)
    assert(configure_color(&r,other_target,other_source) == nil && pipeline_calls == n+2)
    fixture_cleanup(&r)
    glib.g_object_unref(other_source); glib.g_object_unref(other_ctx); glib.g_object_unref(other_target)
    finish(i,&r)
}
working_color_and_transform_order :: proc() {
    for hdr in ([?]bool{false,true}) {
        i := inputs(hdr)
        r := Resources{raw={fb=i.fb}}
        assert(configure_color(&r,i.target,i.srgb) == nil)
        assert(r.target_color == i.target && r.gamma == -1 && r.saturation == -1)
        if hdr { assert(r.working_color != i.srgb && luminances[r.working_color.id].mastering_max == 1000) }
        else { assert(r.working_color == i.srgb) }
        assert(transforms[r.to_srgb.id].source == i.target && transforms[r.to_srgb.id].target == r.working_color)
        assert(transforms[r.to_target.id].source == r.working_color && transforms[r.to_target.id].target == i.target)
        assert(transforms[r.to_srgb.id].flags == 0 && transforms[r.to_target.id].flags == 0)
        finish(i,&r)
    }
    i := inputs()
    i.target.kind=2 // Non-parametric/ICC-like target takes existing non-HDR branch; no gamut policy invented.
    r := Resources{raw={fb=i.fb}}
    assert(configure_color(&r,i.target,i.srgb) == nil && r.working_color == i.srgb)
    finish(i,&r)
}
color_teardown_releases_refs :: proc() {
    i := inputs()
    r := Resources{raw={fb=i.fb},width=17,height=19}
    assert(configure_color(&r,i.srgb,i.srgb) == nil && r.target_is_srgb)
    fixture_cleanup(&r); fixture_cleanup(&r)
    assert(r.to_srgb == nil && r.to_target == nil && r.target_color == nil && r.working_color == nil)
    assert(r.raw.fb == i.fb && r.width == 17 && r.height == 19,"color teardown touched scene ownership")
    assert(glib.live_refs() == 5,"aliased state/context references not balanced")
    finish(i,&r)
}
invalid_inputs_do_not_publish :: proc() {
    i := inputs()
    r := Resources{raw={fb=i.fb}}
    assert(configure_color(&r,i.target,i.srgb) == nil)
    before := r; refs := glib.live_refs()
    assert(configure_color(&r,nil,i.srgb) != nil && r == before)
    assert(configure_color(&r,i.target,nil) != nil && r == before)
    i.fb.ctx=nil
    assert(configure_color(&r,i.target,i.srgb) != nil && r == before)
    assert(glib.live_refs() == refs)
    i.fb.ctx=i.cogl
    finish(i,&r)
}

main :: proc() {
    cases := [?]struct {name: string, run: proc()}{
        {"snippet_failure_preserves_configuration",snippet_failure_preserves_configuration},
        {"constructor_failures_are_atomic",constructor_failures_are_atomic},
        {"failed_configuration_is_retried",failed_configuration_is_retried},
        {"cache_uses_all_inputs",cache_uses_all_inputs},
        {"working_color_and_transform_order",working_color_and_transform_order},
        {"color_teardown_releases_refs",color_teardown_releases_refs},
        {"invalid_inputs_do_not_publish",invalid_inputs_do_not_publish},
    }
    assert(len(os.args) == 2)
    found := false
    for c in cases {
        if os.args[1] != "all" && os.args[1] != c.name { continue }
        c.run()
        fmt.println("PASS",c.name)
        found=true
    }
    if !found { fmt.eprintln("Unknown contract test:",os.args[1]); os.exit(2) }
}
