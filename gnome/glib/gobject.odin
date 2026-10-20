package glib

import "core:c"

GType :: uintptr
GObject :: struct { g_class: rawptr, ref_count: u32, qdata: rawptr }
GObject_Class :: struct {
    g_type: GType,
    construct_properties: rawptr,
    constructor, set_property, get_property: rawptr,
    dispose, finalize: proc "c" (obj: ^GObject),
    dispatch_properties_changed, notify, constructed: rawptr,
    flags, n_construct_properties: uint,
    pspecs: rawptr,
    n_pspecs: uint,
    pdummy: [3]rawptr,
}
Type_Query :: struct { type: GType, type_name: cstring, class_size, instance_size: u32 }
#assert(size_of(GObject_Class) == 136 && offset_of(GObject_Class, dispose) == 40 && offset_of(GObject_Class, finalize) == 48)
#assert(size_of(Type_Query) == 24)

foreign import object "system:gobject-2.0"
foreign object {
    g_type_query :: proc(type: GType, query: ^Type_Query) ---
    g_type_class_peek_parent :: proc(klass: rawptr) -> rawptr ---
    g_type_check_instance_is_a :: proc(instance: rawptr, type: GType) -> b32 ---
    g_type_register_static_simple :: proc(parent: GType, name: cstring, class_size: u32, class_init: proc "c" (rawptr, rawptr), instance_size: u32, instance_init: proc "c" (rawptr, rawptr), flags: u32) -> GType ---
    g_object_new_with_properties :: proc(type: GType, n: u32, names: ^cstring, values: rawptr) -> rawptr ---
    g_object_ref :: proc(obj: rawptr) -> rawptr ---
    g_object_ref_sink :: proc(obj: rawptr) -> rawptr ---
    g_object_unref :: proc(obj: rawptr) ---
    g_object_get :: proc(obj: rawptr, first: cstring, #c_vararg args: ..any) ---
    g_signal_newv :: proc(name: cstring, type: GType, flags: u32, closure, accumulator, accu_data, marshaller: rawptr, return_type: GType, n: u32, params: ^GType) -> u32 ---
    g_signal_emit :: proc(obj: rawptr, signal: u32, detail: u32, #c_vararg args: ..any) ---
    g_signal_connect_data :: proc(obj: rawptr, name: cstring, callback: rawptr, data: rawptr, destroy: rawptr, flags: u32) -> c.ulong ---
    g_signal_handler_disconnect :: proc(obj: rawptr, id: c.ulong) ---
    g_signal_lookup :: proc(name: cstring, type: GType) -> u32 ---
}
