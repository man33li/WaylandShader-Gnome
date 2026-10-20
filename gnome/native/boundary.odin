package waylandshader

import "base:runtime"
import "core:c"
import glib "../glib"

Error :: Maybe(string)

foreign import boundary_glib "system:glib-2.0"
@(default_calling_convention="c")
foreign boundary_glib {
    @(link_name="g_utf8_validate") boundary_utf8_validate :: proc(text: cstring, length: int, end: ^cstring) -> b32 ---
    @(link_name="g_quark_from_static_string") boundary_quark :: proc(text: cstring) -> u32 ---
    @(link_name="g_set_error_literal") boundary_set_error :: proc(error: rawptr, domain: u32, code: c.int, message: cstring) ---
    @(link_name="g_log") boundary_log :: proc(domain: cstring, level: u32, format: cstring, #c_vararg args: ..any) ---
}

boundary_failure :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
    // Length-delimited formatting needs no allocation, even on allocation failure.
    boundary_log(nil, 1<<3, "%.*s: %.*s (%.*s:%d)", c.int(len(prefix)), raw_data(prefix), c.int(len(message)), raw_data(message), c.int(len(loc.file_path)), raw_data(loc.file_path), c.int(loc.line))
    runtime.trap()
}

boundary_context :: proc "contextless" () -> runtime.Context {
    result := runtime.default_context()
    result.assertion_failure_proc = boundary_failure
    return result
}

text :: proc(value: cstring) -> (string, Error) {
    if value == nil || !bool(boundary_utf8_validate(value, -1, nil)) {
        return "", "Invalid UTF-8 argument"
    }
    return string(value), nil
}

mutate :: proc(err: Error, destination: ^^glib.Error) -> b32 {
    if message, failed := err.?; failed {
        // g_set_error_literal copies the string; never hand Odin memory to GLib.
        buffer, allocation_error := make([]u8, len(message)+1)
        if allocation_error != nil {
            boundary_set_error(destination, boundary_quark("wayland-shader-error"), 1, "Out of memory")
            return false
        }
        defer delete(buffer)
        copy(buffer, message)
        boundary_set_error(destination, boundary_quark("wayland-shader-error"), 1, cstring(raw_data(buffer)))
        return false
    }
    return true
}
