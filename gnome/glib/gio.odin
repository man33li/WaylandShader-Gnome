package glib

import "core:c"

DBus_Connection :: struct {}
Async_Result :: struct {}
Cancellable :: struct {}
Variant :: struct {}
Variant_Type :: struct {}
Async_Ready_Callback :: #type proc "c" (source: rawptr, result: ^Async_Result, data: rawptr)
DBus_Signal_Callback :: #type proc "c" (connection: ^DBus_Connection, sender, path, iface, signal: cstring, parameters: ^Variant, data: rawptr)

foreign import gio "system:gio-2.0"
foreign gio {
    g_bus_get_sync :: proc(kind: c.int, cancel: ^Cancellable, error: ^^Error) -> ^DBus_Connection ---
    g_dbus_connection_call :: proc(connection: ^DBus_Connection, bus_name, path, iface, method: cstring, parameters: ^Variant, reply_type: ^Variant_Type, flags: u32, timeout: c.int, cancel: ^Cancellable, callback: Async_Ready_Callback, data: rawptr) ---
    g_dbus_connection_call_finish :: proc(connection: ^DBus_Connection, result: ^Async_Result, error: ^^Error) -> ^Variant ---
    g_dbus_connection_signal_subscribe :: proc(connection: ^DBus_Connection, sender, iface, member, path, arg0: cstring, flags: u32, callback: DBus_Signal_Callback, data: rawptr, destroy: proc "c" (rawptr)) -> u32 ---
    g_dbus_connection_signal_unsubscribe :: proc(connection: ^DBus_Connection, subscription: u32) ---
    g_dbus_error_get_remote_error :: proc(error: ^Error) -> cstring ---
    g_dbus_error_strip_remote_error :: proc(error: ^Error) -> b32 ---
    g_cancellable_new :: proc() -> ^Cancellable ---
    g_cancellable_cancel :: proc(cancel: ^Cancellable) ---
}
foreign import variant_lib "system:glib-2.0"
foreign variant_lib {
    g_variant_new :: proc(format: cstring, #c_vararg args: ..any) -> ^Variant ---
    g_variant_is_of_type :: proc(value: ^Variant, kind: ^Variant_Type) -> b32 ---
    g_variant_get_type_string :: proc(value: ^Variant) -> cstring ---
    g_variant_get_child_value :: proc(value: ^Variant, index: c.size_t) -> ^Variant ---
    g_variant_get_string :: proc(value: ^Variant, length: ^c.size_t) -> cstring ---
    g_variant_get_boolean :: proc(value: ^Variant) -> b32 ---
    g_variant_get_double :: proc(value: ^Variant) -> f64 ---
    g_variant_get_uint32 :: proc(value: ^Variant) -> u32 ---
    g_variant_get_int32 :: proc(value: ^Variant) -> i32 ---
    g_variant_n_children :: proc(value: ^Variant) -> c.size_t ---
    g_variant_lookup_value :: proc(value: ^Variant, key: cstring, expected: ^Variant_Type) -> ^Variant ---
    g_variant_unref :: proc(value: ^Variant) ---
}
