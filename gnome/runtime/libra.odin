package shader_runtime

import "core:fmt"
import "core:strings"

Gl_Filter_Chain :: distinct rawptr
Preset :: distinct rawptr
Libra_Error :: distinct rawptr
Preset_Options :: struct { version: uint, original_aspect_uniforms, frametime_uniforms: bool }
Chain_Options :: struct { version: uint, glsl_version: u16, use_dsa, force_no_mipmaps, disable_cache: bool }
Preset_Parameter :: struct { name, description: cstring, initial, minimum, maximum, step: f32 }
Parameter_List :: struct { parameters: [^]Preset_Parameter, length: u64 }
Image :: struct { handle, format, width, height: u32 }
Viewport :: struct { x, y: f32, width, height: u32 }
Frame_Options :: struct {
    version: uint,
    clear_history: bool,
    frame_direction: i32,
    rotation, total_subframes, current_subframe: u32,
    aspect_ratio, frames_per_second: f32,
    frametime_delta: u32,
}
#assert(size_of(Preset_Options) == 16 && size_of(Chain_Options) == 16)
#assert(size_of(Preset_Parameter) == 32 && size_of(Parameter_List) == 16)
#assert(size_of(Image) == 16 && size_of(Viewport) == 16 && size_of(Frame_Options) == 40)

foreign import libra "system:waylandshader-rashader"
foreign libra {
    libra_error_errno :: proc(err: Libra_Error) -> i32 ---
    libra_error_write :: proc(err: Libra_Error, out: ^cstring) -> i32 ---
    libra_error_free_string :: proc(str: ^cstring) -> i32 ---
    libra_error_free :: proc(err: ^Libra_Error) -> i32 ---
    libra_preset_create_with_options :: proc(filename: cstring, ctx: ^rawptr, options: ^Preset_Options, out: ^Preset) -> Libra_Error ---
    libra_preset_free :: proc(preset: ^Preset) -> Libra_Error ---
    libra_preset_get_runtime_params :: proc(preset: ^Preset, out: ^Parameter_List) -> Libra_Error ---
    libra_preset_free_runtime_params :: proc(list: Parameter_List) -> Libra_Error ---
    libra_gl_filter_chain_create :: proc(preset: ^Preset, loader: proc "c" (cstring) -> rawptr, options: ^Chain_Options, out: ^Gl_Filter_Chain) -> Libra_Error ---
    libra_gl_filter_chain_free :: proc(chain: ^Gl_Filter_Chain) -> Libra_Error ---
    libra_gl_filter_chain_get_active_pass_count :: proc(chain: ^Gl_Filter_Chain, count: ^u32) -> Libra_Error ---
    libra_gl_filter_chain_get_param :: proc(chain: ^Gl_Filter_Chain, name: cstring, value: ^f32) -> Libra_Error ---
    libra_gl_filter_chain_set_param :: proc(chain: ^Gl_Filter_Chain, name: cstring, value: f32) -> Libra_Error ---
    libra_gl_filter_chain_frame :: proc(chain: ^Gl_Filter_Chain, count: uint, source, destination: Image, viewport: ^Viewport, mvp: ^f32, options: ^Frame_Options) -> Libra_Error ---
}

libra_fallback :: proc(code: i32) -> string { return fmt.tprintf("librashader failed (error %d)", code) }
check :: proc(failure: Libra_Error) -> Error {
    if failure == nil { return nil }
    err := failure
    defer libra_error_free(&err)
    message: cstring
    libra_error_write(err, &message)
    if message == nil { return libra_fallback(libra_error_errno(err)) }
    defer libra_error_free_string(&message)
    s, alloc_err := strings.clone(string(message), context.temp_allocator)
    if alloc_err != nil { return "Out of memory" }
    return s
}
