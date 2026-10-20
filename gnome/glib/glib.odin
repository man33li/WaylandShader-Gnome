package glib

import "core:c"

GThread :: struct {}
GMainContext :: struct {}
GMainLoop :: struct {}
GSource :: struct {}
Error :: struct { domain: u32, code: i32, message: cstring }
GList :: struct { data: rawptr, next, prev: ^GList }
#assert(size_of(Error) == 16 && offset_of(Error, domain) == 0 && offset_of(Error, code) == 4 && offset_of(Error, message) == 8)
#assert(size_of(GList) == 24 && offset_of(GList, data) == 0 && offset_of(GList, next) == 8 && offset_of(GList, prev) == 16)

foreign import lib "system:glib-2.0"
foreign lib {
    g_thread_self :: proc() -> ^GThread ---
    g_main_context_ref_thread_default :: proc() -> ^GMainContext ---
    g_main_context_unref :: proc(ctx: ^GMainContext) ---
    g_main_context_iteration :: proc(ctx: ^GMainContext, may_block: b32) -> b32 ---
    g_main_loop_new :: proc(ctx: ^GMainContext, running: b32) -> ^GMainLoop ---
    g_main_loop_run :: proc(loop: ^GMainLoop) ---
    g_main_loop_quit :: proc(loop: ^GMainLoop) ---
    g_main_loop_unref :: proc(loop: ^GMainLoop) ---
    g_idle_source_new :: proc() -> ^GSource ---
    g_source_set_callback :: proc(source: ^GSource, callback: proc "c" (rawptr) -> b32, data: rawptr, destroy: proc "c" (rawptr)) ---
    g_source_attach :: proc(source: ^GSource, ctx: ^GMainContext) -> u32 ---
    g_source_destroy :: proc(source: ^GSource) ---
    g_source_unref :: proc(source: ^GSource) ---
    g_source_remove :: proc(id: u32) -> b32 ---
    g_main_context_find_source_by_id :: proc(ctx: ^GMainContext, id: u32) -> ^GSource ---
    g_timeout_add :: proc(interval: u32, callback: proc "c" (rawptr) -> b32, data: rawptr) -> u32 ---
    g_idle_add :: proc(callback: proc "c" (rawptr) -> b32, data: rawptr) -> u32 ---
    g_once_init_enter :: proc(location: ^uintptr) -> b32 ---
    g_once_init_leave :: proc(location: ^uintptr, result: uintptr) ---
    g_strndup :: proc(str: rawptr, length: c.size_t) -> cstring ---
    g_strdup :: proc(str: cstring) -> cstring ---
    g_free :: proc(data: rawptr) ---
    g_utf8_validate :: proc(str: cstring, length: int, end: ^cstring) -> b32 ---
    g_file_test :: proc(path: cstring, flags: u32) -> b32 ---
    g_quark_from_static_string :: proc(str: cstring) -> u32 ---
    g_set_error_literal :: proc(err: ^^Error, domain: u32, code: i32, message: cstring) ---
    g_error_free :: proc(err: ^Error) ---
    g_log :: proc(domain: cstring, level: u32, format: cstring, #c_vararg args: ..any) ---
    g_get_monotonic_time :: proc() -> i64 ---
    g_set_prgname :: proc(name: cstring) ---
}
