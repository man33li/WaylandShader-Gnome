package waylandshader

import "core:c"
import glib "../glib"

Actor :: struct {}
Actor_Meta :: struct {}
Paint_Context :: struct {}
Stage_View :: struct {}
Timeline :: struct {}
Frame :: struct {}
Frame_Clock_Handle :: struct {}
Meta_Backend :: struct {}
Color_State :: struct {}
Cogl_Context :: struct {}
Texture :: struct {}
Framebuffer :: struct {}
Pipeline :: struct {}
Mtk_Rectangle :: struct { x,y,width,height: i32 }
Matrix :: struct #align(16) { values: [16]f32 }
Luminance :: struct { kind: u32, minimum, maximum, reference, mastering_max: f32 }
Actor_Meta_Class :: struct {
    using parent: glib.GObject_Class,
    set_actor: proc "c" (meta: ^Actor_Meta, actor: ^Actor),
    set_enabled: rawptr,
}
Effect_Class :: struct {
    using meta_parent: Actor_Meta_Class,
    pre_paint, post_paint, modify_paint_volume: rawptr,
    paint: proc "c" (effect: ^Effect, node: rawptr, pc: ^Paint_Context, flags: u32),
    paint_node, pick: rawptr,
}
Effect :: struct { parent_instance: [3]rawptr, engine: ^Engine }
#assert(size_of(Actor_Meta_Class) == 152 && offset_of(Actor_Meta_Class, set_actor) == 136 && offset_of(Actor_Meta_Class, set_enabled) == 144)
#assert(size_of(Effect_Class) == 200 && offset_of(Effect_Class, pre_paint) == 152 && offset_of(Effect_Class, post_paint) == 160 && offset_of(Effect_Class, modify_paint_volume) == 168)
#assert(offset_of(Effect_Class, paint) == 176 && offset_of(Effect_Class, paint_node) == 184 && offset_of(Effect_Class, pick) == 192)
#assert(size_of(Effect) == 32 && size_of([3]rawptr) == 24 && offset_of(Effect, parent_instance) == 0 && offset_of(Effect, engine) == 24)
#assert(size_of(Mtk_Rectangle) == 16 && offset_of(Mtk_Rectangle, x) == 0 && offset_of(Mtk_Rectangle, y) == 4 && offset_of(Mtk_Rectangle, width) == 8 && offset_of(Mtk_Rectangle, height) == 12)
#assert(size_of(Matrix) == 64 && align_of(Matrix) == 16 && offset_of(Matrix, values) == 0)
#assert(size_of(Luminance) == 20 && offset_of(Luminance, minimum) == 4 && offset_of(Luminance, maximum) == 8 && offset_of(Luminance, reference) == 12 && offset_of(Luminance, mastering_max) == 16)

foreign import clutter "system:mutter-clutter-18"
foreign clutter {
    clutter_effect_get_type :: proc() -> glib.GType ---
    clutter_stage_get_type :: proc() -> glib.GType ---
    clutter_actor_meta_get_actor :: proc(meta: ^Actor_Meta) -> ^Actor ---
    clutter_actor_continue_paint :: proc(actor: ^Actor, pc: ^Paint_Context) ---
    clutter_actor_get_context :: proc(actor: ^Actor) -> rawptr ---
    clutter_actor_queue_redraw :: proc(actor: ^Actor) ---
    clutter_actor_queue_redraw_with_clip :: proc(actor: ^Actor, clip: ^Mtk_Rectangle) ---
    clutter_stage_view_add_redraw_clip :: proc(view: ^Stage_View, clip: ^Mtk_Rectangle) ---
    clutter_stage_view_schedule_update :: proc(view: ^Stage_View) ---
    clutter_stage_view_get_layout :: proc(view: ^Stage_View, layout: ^Mtk_Rectangle) ---
    clutter_stage_view_get_framebuffer :: proc(view: ^Stage_View) -> ^Framebuffer ---
    clutter_stage_view_get_frame_clock :: proc(view: ^Stage_View) -> ^Frame_Clock_Handle ---
    clutter_frame_clock_get_refresh_rate :: proc(clock: ^Frame_Clock_Handle) -> f32 ---
    clutter_frame_get_count :: proc(frame: ^Frame) -> i64 ---
    clutter_frame_get_expected_presentation_time :: proc(frame: ^Frame, time: ^i64) -> b32 ---
    clutter_timeline_new_for_frame_clock :: proc(clock: ^Frame_Clock_Handle, duration: u32) -> ^Timeline ---
    clutter_timeline_set_repeat_count :: proc(timeline: ^Timeline, count: i32) ---
    clutter_timeline_start :: proc(timeline: ^Timeline) ---
    clutter_timeline_stop :: proc(timeline: ^Timeline) ---
    clutter_paint_context_get_stage_view :: proc(pc: ^Paint_Context) -> ^Stage_View ---
    clutter_paint_context_get_frame :: proc(pc: ^Paint_Context) -> ^Frame ---
    clutter_paint_context_get_framebuffer :: proc(pc: ^Paint_Context) -> ^Framebuffer ---
    clutter_paint_context_get_target_color_state :: proc(pc: ^Paint_Context) -> ^Color_State ---
    clutter_color_state_params_get_type :: proc() -> glib.GType ---
    clutter_color_state_params_get_luminance :: proc(state: ^Color_State) -> ^Luminance ---
    clutter_color_state_params_new :: proc(ctx: rawptr, colorspace, transfer: u32) -> ^Color_State ---
    clutter_color_state_params_new_full :: proc(ctx: rawptr, colorspace, transfer: u32, primaries: rawptr, gamma, minimum, maximum, reference, mastering_max: f32) -> ^Color_State ---
    clutter_color_state_equals :: proc(a,b: ^Color_State) -> b32 ---
    clutter_color_state_add_pipeline_transform :: proc(a,b: ^Color_State, pipeline: ^Pipeline, flags: u32) ---
    clutter_color_state_update_uniforms :: proc(a,b: ^Color_State, pipeline: ^Pipeline) ---
}
foreign import mutter "system:mutter-18"
foreign mutter {
    meta_renderer_view_get_type :: proc() -> glib.GType ---
    meta_renderer_view_get_crtc :: proc(view: ^Stage_View) -> rawptr ---
    meta_crtc_get_backend :: proc(crtc: rawptr) -> ^Meta_Backend ---
    meta_crtc_get_outputs :: proc(crtc: rawptr) -> ^glib.GList ---
    meta_output_get_assigned_crtc :: proc(output: rawptr) -> rawptr ---
    meta_monitor_get_outputs :: proc(monitor: rawptr) -> ^glib.GList ---
    meta_monitor_get_connector :: proc(monitor: rawptr) -> cstring ---
    meta_monitor_is_active :: proc(monitor: rawptr) -> b32 ---
    meta_backend_get_monitor_manager :: proc(backend: ^Meta_Backend) -> rawptr ---
    meta_monitor_manager_get_monitors :: proc(manager: rawptr) -> ^glib.GList ---
    meta_backend_get_renderer :: proc(backend: ^Meta_Backend) -> rawptr ---
    meta_renderer_get_view_for_crtc :: proc(renderer,crtc: rawptr) -> ^Stage_View ---
    meta_backend_inhibit_hw_cursor :: proc(backend: ^Meta_Backend) ---
    meta_backend_uninhibit_hw_cursor :: proc(backend: ^Meta_Backend) ---
}
foreign import cogl "system:mutter-cogl-18"
foreign cogl {
    cogl_texture_2d_new_with_format :: proc(ctx: ^Cogl_Context, width,height: i32, format: u32) -> ^Texture ---
    cogl_texture_2d_set_auto_mipmap :: proc(texture: ^Texture, enabled: b32) ---
    cogl_texture_allocate :: proc(texture: ^Texture, err: ^^glib.Error) -> b32 ---
    cogl_offscreen_new_with_texture :: proc(texture: ^Texture) -> ^Framebuffer ---
    cogl_framebuffer_allocate :: proc(fb: ^Framebuffer, err: ^^glib.Error) -> b32 ---
    cogl_framebuffer_set_modelview_matrix :: proc(fb: ^Framebuffer, value: ^Matrix) ---
    cogl_framebuffer_orthographic :: proc(fb: ^Framebuffer, x1,y1,x2,y2,near,far: f32) ---
    cogl_framebuffer_set_viewport :: proc(fb: ^Framebuffer, x,y,width,height: f32) ---
    cogl_framebuffer_clear4f :: proc(fb: ^Framebuffer, buffers: c.ulong, r,g,b,a: f32) ---
    cogl_framebuffer_get_context :: proc(fb: ^Framebuffer) -> ^Cogl_Context ---
    cogl_framebuffer_get_width :: proc(fb: ^Framebuffer) -> i32 ---
    cogl_framebuffer_get_height :: proc(fb: ^Framebuffer) -> i32 ---
    cogl_framebuffer_flush :: proc(fb: ^Framebuffer) ---
    cogl_context_flush :: proc(ctx: ^Cogl_Context) ---
    cogl_framebuffer_blit :: proc(source,destination: ^Framebuffer, sx,sy,dx,dy,width,height: i32, err: ^^glib.Error) -> b32 ---
    cogl_texture_get_gl_texture :: proc(texture: ^Texture, name,target: ^u32) -> b32 ---
    cogl_pipeline_new :: proc(ctx: ^Cogl_Context) -> ^Pipeline ---
    cogl_pipeline_set_blend :: proc(p: ^Pipeline, expression: cstring, err: ^^glib.Error) -> b32 ---
    cogl_pipeline_set_layer_filters :: proc(p: ^Pipeline, layer: i32, min,mag: u32) ---
    cogl_pipeline_set_layer_wrap_mode :: proc(p: ^Pipeline, layer: i32, mode: u32) ---
    cogl_snippet_new :: proc(hook: u32, declarations,body: cstring) -> rawptr ---
    cogl_pipeline_add_layer_snippet :: proc(p: ^Pipeline, layer: i32, snippet: rawptr) ---
    cogl_pipeline_get_uniform_location :: proc(p: ^Pipeline, name: cstring) -> i32 ---
    cogl_pipeline_set_uniform_1f :: proc(p: ^Pipeline, location: i32, value: f32) ---
    cogl_pipeline_set_layer_texture :: proc(p: ^Pipeline, layer: i32, texture: ^Texture) ---
    cogl_framebuffer_draw_textured_rectangle :: proc(fb: ^Framebuffer, p: ^Pipeline, x1,y1,x2,y2,s1,t1,s2,t2: f32) ---
}
