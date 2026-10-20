package waylandshader

import "base:runtime"
import "core:c"
import common "../common"
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
    result := string(value)
    // QString::fromUtf8 removes one initial BOM, not a second or an interior one.
    if len(result)>=3 && result[:3]=="\xef\xbb\xbf" { result=result[3:] }
    return result, nil
}

mutate :: proc(err: Error, destination: ^^glib.Error) -> b32 {
    if message, failed := err.?; failed {
        safe,encoding_error:=common.text_utf8(message,context.temp_allocator)
        if encoding_error!=nil {
            boundary_set_error(destination,boundary_quark("wayland-shader-error"),1,"Out of memory")
            return false
        }
        // g_set_error_literal copies the string; never hand Odin memory to GLib.
        buffer, allocation_error := make([]u8, len(safe)+1)
        if allocation_error != nil {
            boundary_set_error(destination, boundary_quark("wayland-shader-error"), 1, "Out of memory")
            return false
        }
        defer delete(buffer)
        copy(buffer, safe)
        boundary_set_error(destination, boundary_quark("wayland-shader-error"), 1, cstring(raw_data(buffer)))
        return false
    }
    return true
}
