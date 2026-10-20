package waylandshader

import "base:runtime"
import glib "../glib"

type_id: uintptr
parent_class: ^Effect_Class
status_signal: u32

@(export)
wayland_shader_effect_get_type :: proc "c" () -> glib.GType {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    if glib.g_once_init_enter(&type_id) {
        q: glib.Type_Query
        parent := clutter_effect_get_type()
        glib.g_type_query(parent, &q)
        t: glib.GType
        if q.class_size == size_of(Effect_Class) && q.instance_size == 24 {
            t = glib.g_type_register_static_simple(parent, "WaylandShaderEffect", size_of(Effect_Class), class_init, size_of(Effect), instance_init, 0)
        } else {
            glib.g_log(nil, 8, "WaylandShader: incompatible ClutterEffect layout")
        }
        // g_once_init_leave requires a nonzero sentinel even when registration was refused.
        glib.g_once_init_leave(&type_id, t if t != 0 else ~uintptr(0))
    }
    return 0 if type_id == ~uintptr(0) else type_id
}

class_init :: proc "c" (klass, data: rawptr) {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    k := cast(^Effect_Class)klass
    parent_class = cast(^Effect_Class)glib.g_type_class_peek_parent(klass)
    k.dispose = dispose
    k.finalize = finalize
    k.set_actor = set_actor
    k.paint = paint
    param: glib.GType = 64
    status_signal = glib.g_signal_newv("status-changed", k.g_type, 2, nil, nil, nil, nil, 4, 1, &param)
}

instance_init :: proc "c" (instance, klass: rawptr) {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    self := cast(^Effect)instance
    e, err := new(Engine)
    if err != nil { return }
    e.self = self
    e.owner = glib.g_thread_self()
    e.main_ctx = glib.g_main_context_ref_thread_default()
    e.enabled = true
    e.mapping_dirty = true
    e.next_key = 1
    self.engine = e
}

@(export)
wayland_shader_effect_new :: proc "c" () -> ^Effect {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    t := wayland_shader_effect_get_type()
    if t == 0 { return nil }
    self := cast(^Effect)glib.g_object_new_with_properties(t, 0, nil, nil)
    if self == nil { return nil }
    if self.engine == nil { glib.g_object_unref(self); return nil }
    glib.g_object_ref_sink(self)
    return self
}

@(export)
wayland_shader_effect_get_status :: proc "c" (self: ^Effect) -> cstring {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    if self != nil && glib.g_type_check_instance_is_a(self,wayland_shader_effect_get_type()) && self.engine != nil {
        value, err := status_json(self.engine)
        if err == nil { defer delete(value); return glib.g_strndup(raw_data(value), len(value)) }
    }
    return glib.g_strdup("{\"enabled\":false,\"active\":false,\"loading\":false,\"preset\":\"\",\"requestedPreset\":\"\",\"error\":\"Unable to construct native status\",\"parameters\":[],\"outputs\":[]}")
}

@(export)
wayland_shader_effect_shutdown :: proc "c" (self: ^Effect) {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    if self != nil && glib.g_type_check_instance_is_a(self,wayland_shader_effect_get_type()) && self.engine != nil { engine_shutdown(self.engine) }
}

dispose :: proc "c" (obj: ^glib.GObject) {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    wayland_shader_effect_shutdown(cast(^Effect)obj)
    if parent_class.dispose != nil { parent_class.dispose(obj) }
}

finalize :: proc "c" (obj: ^glib.GObject) {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    self := cast(^Effect)obj
    if self.engine != nil {
        engine_destroy(self.engine)
        self.engine = nil
    }
    if parent_class.finalize != nil { parent_class.finalize(obj) }
}

set_actor :: proc "c" (meta: ^Actor_Meta, actor: ^Actor) {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    parent_class.set_actor(meta, actor)
    e := (cast(^Effect)meta).engine
    if e != nil { if err := attach(e,actor); err != nil { fail(e,error_message(err)) } }
}

paint :: proc "c" (effect: ^Effect, node: rawptr, pc: ^Paint_Context, flags: u32) {
    context = boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    continued := false
    if effect.engine != nil { if err := engine_paint(effect.engine,pc,flags,&continued); err != nil { renderer_failure(effect.engine,err) } }
    if !continued { actor := clutter_actor_meta_get_actor(cast(^Actor_Meta)effect); if actor != nil { clutter_actor_continue_paint(actor,pc) } }
}
