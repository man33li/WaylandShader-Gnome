package shader_runtime

import "core:fmt"
import "core:strings"

Display :: distinct rawptr
Context :: distinct rawptr
Surface :: distinct rawptr
Config :: distinct rawptr
Error :: Maybe(string)
NONE :: 0x3038
DRAW :: 0x3059
READ :: 0x305a
OPENGL_API :: 0x30a2
OPENGL_BIT :: 8
PBUFFER_BIT :: 1
SURFACE_TYPE :: 0x3033
RENDERABLE_TYPE :: 0x3040
WIDTH :: 0x3057
HEIGHT :: 0x3056
CONTEXT_CLIENT_TYPE :: 0x3097
CONTEXT_MAJOR_VERSION :: 0x3098
CONTEXT_MINOR_VERSION :: 0x30fb
CONTEXT_OPENGL_PROFILE_MASK :: 0x30fd
CONTEXT_OPENGL_CORE_PROFILE_BIT :: 1
CONTEXT_FLAGS :: 0x30fc
CONTEXT_OPENGL_ROBUST_ACCESS_BIT :: 4
CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY :: 0x31bd
LOSE_CONTEXT_ON_RESET :: 0x31bf
NO_RESET_NOTIFICATION :: 0x31be
VERSION :: 0x3054
EXTENSIONS :: 0x3055
PLATFORM_SURFACELESS_MESA :: 0x31dd

foreign import egl "system:EGL"
foreign egl {
    @(link_name="eglGetDisplay") GetDisplay :: proc(native: rawptr) -> Display ---
    @(link_name="eglGetPlatformDisplay") GetPlatformDisplay :: proc(platform: u32, native: rawptr, attribs: ^int) -> Display ---
    @(link_name="eglInitialize") Initialize :: proc(display: Display, major, minor: ^i32) -> b32 ---
    @(link_name="eglTerminate") Terminate :: proc(display: Display) -> b32 ---
    @(link_name="eglGetProcAddress") GetProcAddress :: proc(name: cstring) -> rawptr ---
    @(link_name="eglGetCurrentDisplay") GetCurrentDisplay :: proc() -> Display ---
    @(link_name="eglGetCurrentContext") GetCurrentContext :: proc() -> Context ---
    @(link_name="eglGetCurrentSurface") GetCurrentSurface :: proc(which: i32) -> Surface ---
    @(link_name="eglQueryAPI") QueryAPI :: proc() -> u32 ---
    @(link_name="eglBindAPI") BindAPI :: proc(api: u32) -> b32 ---
    @(link_name="eglMakeCurrent") MakeCurrent :: proc(display: Display, draw, read: Surface, ctx: Context) -> b32 ---
    @(link_name="eglQueryContext") QueryContext :: proc(display: Display, ctx: Context, attribute: i32, value: ^i32) -> b32 ---
    @(link_name="eglGetError") GetError :: proc() -> i32 ---
    @(link_name="eglQueryString") QueryString :: proc(display: Display, name: i32) -> cstring ---
    @(link_name="eglChooseConfig") ChooseConfig :: proc(display: Display, attribs: ^i32, config: ^Config, capacity: i32, count: ^i32) -> b32 ---
    @(link_name="eglCreateContext") CreateContext :: proc(display: Display, config: Config, share: Context, attribs: ^i32) -> Context ---
    @(link_name="eglCreatePbufferSurface") CreatePbufferSurface :: proc(display: Display, config: Config, attribs: ^i32) -> Surface ---
    @(link_name="eglDestroyContext") DestroyContext :: proc(display: Display, ctx: Context) -> b32 ---
    @(link_name="eglDestroySurface") DestroySurface :: proc(display: Display, surface: Surface) -> b32 ---
}

egl_error_code :: proc(operation: string, code: i32) -> string { return fmt.tprintf("%s failed (EGL error 0x%04x)", operation, code) }
egl_error :: proc(operation: string) -> Error { return egl_error_code(operation, GetError()) }
has_extension :: proc(display: Display, extension: string) -> bool {
    all := QueryString(display, EXTENSIONS)
    if all == nil { return false }
    remaining := string(all)
    for token in strings.split_iterator(&remaining, " ") { if token == extension { return true } }
    return false
}
Current_Context :: struct {
    target, display: Display,
    ctx: Context,
    draw, read: Surface,
    api: u32,
    changed: bool,
}
save_context :: proc(target: Display) -> Current_Context {
    return {target=target, display=GetCurrentDisplay(), ctx=GetCurrentContext(), draw=GetCurrentSurface(DRAW), read=GetCurrentSurface(READ), api=QueryAPI()}
}
enter :: proc(c: ^Current_Context, ctx: Context, surface: Surface) -> Error {
    c.changed = true
    if !BindAPI(OPENGL_API) { return egl_error("eglBindAPI(OpenGL)") }
    if !MakeCurrent(c.target, surface, surface, ctx) { return egl_error("eglMakeCurrent(private shader context)") }
    return nil
}
restore :: proc(c: ^Current_Context) -> Error {
    if !c.changed { return nil }
    if !BindAPI(OPENGL_API) || !MakeCurrent(c.target, nil, nil, nil) { return egl_error("eglMakeCurrent(releasing shader context)") }
    if !BindAPI(c.api) { return egl_error("eglBindAPI(restoring caller)") }
    if c.ctx != nil && !MakeCurrent(c.display, c.draw, c.read, c.ctx) { return egl_error("eglMakeCurrent(restoring caller)") }
    c.changed = false
    return nil
}
