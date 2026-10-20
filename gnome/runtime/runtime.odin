package shader_runtime

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:slice"
import gl "vendor:OpenGL"
import glib "../glib"
import common "../common"

Parameter :: struct { name, description: string, minimum, maximum, step, default_value, value: f64 }
Frame :: struct { number: u64, source, destination, format: u32, width, height: i32, fps: f32, elapsed_ms: u32, clear_history: bool }
#assert(size_of(Frame) == 40)
Runtime :: struct {
    display: Display,
    ctx, host: Context,
    surface: Surface,
    surfaceless: bool,
    max_texture_size: i32,
    keys: [dynamic]uintptr,
    chains: [dynamic]Gl_Filter_Chain,
    parameters: [dynamic]Parameter,
    names: [dynamic]cstring,
}
gl_loaded: bool
set_gl_proc :: proc(p: rawptr, name: cstring) { (cast(^rawptr)p)^ = GetProcAddress(name) }
ensure_gl_loaded :: proc() { if !gl_loaded { gl.load_up_to(4, 6, set_gl_proc); gl_loaded = true } }

foreign import libc "system:c"
foreign libc {
    @(link_name="realpath") canonical_path :: proc(path: cstring, resolved: rawptr) -> cstring ---
    @(link_name="access") file_access :: proc(path: cstring, mode: i32) -> i32 ---
    @(link_name="free") c_free :: proc(p: rawptr) ---
}

message :: proc(err: Error) -> string { if s, ok := err.?; ok { return s }; return "" }
cleanup_error :: proc(err: Error) { if s, ok := err.?; ok { glib.g_log(nil, 16, "WaylandShader cleanup: %.*s", i32(len(s)), raw_data(s)) } }
validate_value :: proc(p: ^Parameter, candidate: f64) -> Error {
    value := f32(candidate)
    if math.is_nan(value) || math.is_inf(value) || f64(value) < p.minimum || f64(value) > p.maximum {
        return fmt.tprintf("Parameter '%s' must be finite and between %.9g and %.9g", p.name, p.minimum, p.maximum)
    }
    return nil
}

create_context :: proc(rt: ^Runtime) -> Error {
    api: i32
    if !QueryContext(rt.display, rt.host, CONTEXT_CLIENT_TYPE, &api) { return egl_error("eglQueryContext(host API)") }
    if api != OPENGL_API { return "WaylandShader requires a desktop OpenGL EGL renderer, not OpenGL ES" }
    previous := QueryAPI()
    if !BindAPI(OPENGL_API) { return egl_error("eglBindAPI(OpenGL)") }
    result:=create_bound_context(rt)
    if !BindAPI(previous) { return egl_error("eglBindAPI(restoring caller)") }
    return result
}

create_bound_context :: proc(rt: ^Runtime) -> Error {
    version:=QueryString(rt.display,VERSION)
    major,minor,index:=0,0,0
    if version!=nil {
        text:=string(version)
        for index<len(text) && text[index]>='0' && text[index]<='9' { major=major*10+int(text[index]-'0'); index+=1 }
        if index<len(text) && text[index]=='.' { index+=1; for index<len(text) && text[index]>='0' && text[index]<='9' { minor=minor*10+int(text[index]-'0'); index+=1 } }
    }
    rt.surfaceless=major>1 || major==1 && minor>=5 || has_extension(rt.display,"EGL_KHR_surfaceless_context")
    attributes := [?]i32{SURFACE_TYPE, 0 if rt.surfaceless else PBUFFER_BIT, RENDERABLE_TYPE, OPENGL_BIT, NONE}
    config: Config
    count: i32
    if !ChooseConfig(rt.display, &attributes[0], &config, 1, &count) { return egl_error("eglChooseConfig(OpenGL)") }
    if count == 0 { return fmt.tprintf("The compositor's EGL display has no suitable OpenGL %s config", "surfaceless" if rt.surfaceless else "pbuffer") }
    for version in ([?][2]i32{{4,6}, {4,5}, {3,3}}) {
        for robust in ([?]bool{false, true}) {
            attrs := [?]i32{CONTEXT_MAJOR_VERSION, version[0], CONTEXT_MINOR_VERSION, version[1], CONTEXT_OPENGL_PROFILE_MASK, CONTEXT_OPENGL_CORE_PROFILE_BIT, NONE, 0, 0, 0, NONE}
            if robust { attrs[6] = CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY; attrs[7] = LOSE_CONTEXT_ON_RESET; attrs[8] = CONTEXT_FLAGS; attrs[9] = CONTEXT_OPENGL_ROBUST_ACCESS_BIT }
            rt.ctx = CreateContext(rt.display, config, rt.host, &attrs[0])
            if rt.ctx != nil { break }
        }
        if rt.ctx != nil { break }
    }
    if rt.ctx == nil { return egl_error("eglCreateContext(shared OpenGL 3.3 or newer)") }
    if !rt.surfaceless {
        attrs := [?]i32{WIDTH, 1, HEIGHT, 1, NONE}
        rt.surface = CreatePbufferSurface(rt.display, config, &attrs[0])
        if rt.surface == nil { return egl_error("eglCreatePbufferSurface") }
    }
    return nil
}

has_gl_extension :: proc(name: string) -> bool {
    count: i32
    gl.GetIntegerv(gl.NUM_EXTENSIONS, &count)
    for i in 0..<count { if string(gl.GetStringi(gl.EXTENSIONS, u32(i))) == name { return true } }
    return false
}

load :: proc(display: Display, share: Context, path: string, keys: []uintptr, overrides: map[string]f64) -> (^Runtime,string) {
    result,failure:=load_private(display,share,path,keys,overrides)
    if result!=nil { return result,"" }
    copied,allocation_error:=strings.clone(failure if len(failure)>0 else "Preset compilation failed")
    // Empty failure is the allocation-free OOM sentinel; every nonempty failure is caller-owned.
    if allocation_error!=nil { return nil,"" }
    return nil,copied
}

load_private :: proc(display: Display, share: Context, path: string, keys: []uintptr, overrides: map[string]f64) -> (result: ^Runtime, failure: string) {
    rt: ^Runtime
    defer if result==nil && rt!=nil { destroy(rt) }
    if display == nil || share == nil { return nil, "No desktop OpenGL EGL compositor context is available" }
    p, pe := strings.clone_to_cstring(path, context.temp_allocator)
    if pe != nil { return nil, "Out of memory" }
    if len(path) == 0 || path[0] != '/' || strings.contains_rune(path, 0) || !glib.g_file_test(p,1) || file_access(p, 4) != 0 { return nil, fmt.tprintf("Shader preset must be an absolute path to a readable file: %s", path) }
    canonical := canonical_path(p, nil)
    if canonical == nil { return nil, fmt.tprintf("Shader preset must be an absolute path to a readable file: %s", path) }
    defer c_free(rawptr(canonical))
    alloc_err: runtime.Allocator_Error
    rt, alloc_err = new(Runtime)
    if alloc_err != nil { return nil, "Out of memory" }
    rt.display = display; rt.host = share
    for key, i in keys {
        for prior in keys[:i] { if prior == key { return nil, "An output was supplied more than once while loading the shader" } }
        if _, err := append(&rt.keys, key); err != nil { return nil, "Out of memory" }
    }
    count := max(1, len(keys))
    rt.chains, alloc_err = make([dynamic]Gl_Filter_Chain, count)
    if alloc_err != nil { return nil, "Out of memory" }
    if err := create_context(rt); err != nil { return nil, message(err) }
    current := save_context(display)
    defer cleanup_error(restore(&current))
    if err := enter(&current, rt.ctx, rt.surface); err != nil { return nil, message(err) }
    major, minor: i32
    gl.GetIntegerv(gl.MAJOR_VERSION, &major); gl.GetIntegerv(gl.MINOR_VERSION, &minor)
    version := major*10+minor
    if version < 33 || version < 42 && !has_gl_extension("GL_ARB_texture_storage") { return nil, "librashader requires desktop OpenGL 3.3 and GL_ARB_texture_storage (or OpenGL 4.2)" }
    gl.GetIntegerv(gl.MAX_TEXTURE_SIZE, &rt.max_texture_size)
    preset_options := Preset_Options{2, true, true}
    chain_options := Chain_Options{version=2, glsl_version=u16(version*10), use_dsa=version>=45}
    for &chain, chain_index in rt.chains {
        preset: Preset
        defer if preset != nil { cleanup_error(check(libra_preset_free(&preset))) }
        if err := check(libra_preset_create_with_options(canonical, nil, &preset_options, &preset)); err != nil { return nil, fmt.tprintf("Could not load '%s': %s", path, message(err)) }
        if chain_index == 0 {
            list: Parameter_List
            if err := check(libra_preset_get_runtime_params(&preset, &list)); err != nil { return nil, message(err) }
            defer cleanup_error(check(libra_preset_free_runtime_params(list)))
            for meta in list.parameters[:int(list.length)] {
                parameter := Parameter{name=string(meta.name), description=string(meta.description), minimum=f64(meta.minimum), maximum=f64(meta.maximum), step=f64(meta.step), default_value=f64(meta.initial), value=f64(meta.initial)}
                validation := validate_value(&parameter, parameter.default_value)
                if len(parameter.name) == 0 || math.is_nan(parameter.minimum) || math.is_inf(parameter.minimum) || math.is_nan(parameter.maximum) || math.is_inf(parameter.maximum) || parameter.minimum > parameter.maximum || math.is_nan(parameter.step) || math.is_inf(parameter.step) || parameter.step < 0 || validation != nil { return nil, fmt.tprintf("Invalid shader metadata for parameter '%s': %s", parameter.name, message(validation)) }
                name, ne := strings.clone(parameter.name)
                if ne != nil { return nil, "Out of memory" }
                description, de := strings.clone(parameter.description)
                if de != nil { delete(name); return nil, "Out of memory" }
                parameter.name = name; parameter.description = description
                found := false
                for &old in rt.parameters { if old.name == name { delete(old.name); delete(old.description); old = parameter; found = true; break } }
                if !found { if _, err := append(&rt.parameters, parameter); err != nil { delete(name); delete(description); return nil, "Out of memory" } }
            }
            slice.sort_by(rt.parameters[:], proc(a,b: Parameter)->bool { return common.utf16_less(a.name,b.name) })
            for parameter in rt.parameters {
                name, err := strings.clone_to_cstring(parameter.name)
                if err != nil { return nil, "Out of memory" }
                if _, ae := append(&rt.names, name); ae != nil { delete(name); return nil, "Out of memory" }
            }
            for name, value in overrides {
                found := false
                for &parameter in rt.parameters { if parameter.name == name { found = true; if err := validate_value(&parameter, value); err != nil { return nil, message(err) }; break } }
                if !found { return nil, fmt.tprintf("Unknown shader parameter '%s'", name) }
            }
        }
        if err := check(libra_gl_filter_chain_create(&preset, GetProcAddress, &chain_options, &chain)); err != nil { return nil, fmt.tprintf("Could not compile '%s': %s", path, message(err)) }
        passes: u32
        if err := check(libra_gl_filter_chain_get_active_pass_count(&chain, &passes)); err != nil { return nil, message(err) }
        if passes == 0 { return nil, "Shader preset has no active passes" }
        for &parameter, i in rt.parameters {
            value: f32
            if err := check(libra_gl_filter_chain_get_param(&chain, rt.names[i], &value)); err != nil { return nil, message(err) }
            if err := validate_value(&parameter, f64(value)); err != nil { return nil, message(err) }
            if override, ok := overrides[parameter.name]; ok {
                value = f32(override)
                if err := check(libra_gl_filter_chain_set_param(&chain, rt.names[i], value)); err != nil { return nil, message(err) }
            }
            if chain_index > 0 && parameter.value != f64(value) { return nil, fmt.tprintf("Preset parameter '%s' changed while loading the output chains", parameter.name) }
            parameter.value = f64(value)
        }
    }
    if len(keys) == 0 {
        if err := check(libra_gl_filter_chain_free(&rt.chains[0])); err != nil { return nil, message(err) }
        clear(&rt.chains)
    }
    gl.Flush()
    if err := restore(&current); err != nil { return nil, message(err) }
    return rt, ""
}

set_parameter :: proc(rt: ^Runtime, name: string, candidate: f64) -> Error {
    index := -1
    for p, i in rt.parameters { if p.name == name { index = i; break } }
    if index < 0 { return fmt.tprintf("Unknown shader parameter '%s'", name) }
    p := &rt.parameters[index]
    if err := validate_value(p, candidate); err != nil { return err }
    value := f32(candidate)
    if p.value == f64(value) { return nil }
    previous, ae := make([]f32, len(rt.chains), context.temp_allocator)
    if ae != nil { return "Out of memory" }
    for &chain, i in rt.chains { if err := check(libra_gl_filter_chain_get_param(&chain, rt.names[index], &previous[i])); err != nil { return err } }
    for &chain, i in rt.chains {
        if err := check(libra_gl_filter_chain_set_param(&chain, rt.names[index], value)); err != nil {
            result := message(err)
            for &earlier, j in rt.chains[:i+1] {
                if rollback := check(libra_gl_filter_chain_set_param(&earlier, rt.names[index], previous[j])); rollback != nil { result = fmt.tprintf("%s; restoring output %d failed: %s", result, j, message(rollback)) }
            }
            return result
        }
    }
    p.value = f64(value)
    return nil
}

render :: proc(rt: ^Runtime, key: uintptr, f: ^Frame) -> Error {
    index := -1
    for k, i in rt.keys { if k == key { index = i; break } }
    if index < 0 { return "No shader chain was loaded for this output" }
    if f.source == 0 || f.destination == 0 || f.source == f.destination || f.format == 0 || f.width <= 0 || f.height <= 0 || f.width > rt.max_texture_size || f.height > rt.max_texture_size || math.is_nan(f.fps) || math.is_inf(f.fps) || f.fps <= 0 { return "Invalid shader frame: distinct textures, valid dimensions/format and positive finite frame rate are required" }
    if GetCurrentDisplay() != rt.display || GetCurrentContext() != rt.host || QueryAPI() != OPENGL_API { return "Shader rendering must run with the original compositor OpenGL EGL context current" }
    incoming := gl.FenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0)
    if incoming == nil { return "Could not create the compositor-to-shader GPU fence" }
    gl.Flush()
    current := save_context(rt.display)
    defer cleanup_error(restore(&current))
    if err := enter(&current, rt.ctx, rt.surface); err != nil {
        if re := restore(&current); re != nil { return fmt.tprintf("%s; %s", message(err), message(re)) }
        gl.DeleteSync(incoming)
        return err
    }
    gl.WaitSync(incoming, 0, gl.TIMEOUT_IGNORED); gl.DeleteSync(incoming)
    source := Image{f.source, f.format, u32(f.width), u32(f.height)}
    destination := Image{f.destination, f.format, source.width, source.height}
    options := Frame_Options{version=2, clear_history=f.clear_history, frame_direction=1, total_subframes=1, current_subframe=1, aspect_ratio=f32(f.width)/f32(f.height), frames_per_second=f.fps, frametime_delta=f.elapsed_ms}
    mvp := [16]f32{2,0,0,0, 0,2,0,0, 0,0,0,0, -1,-1,0,1}
    err := check(libra_gl_filter_chain_frame(&rt.chains[index], uint(f.number), source, destination, nil, &mvp[0], &options))
    outgoing := gl.FenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0)
    gl.Flush()
    if outgoing == nil { err = "Could not create the shader-to-compositor GPU fence" }
    if re := restore(&current); re != nil { return re }
    if outgoing != nil { gl.WaitSync(outgoing, 0, gl.TIMEOUT_IGNORED); gl.DeleteSync(outgoing) }
    return err
}

destroy :: proc(rt: ^Runtime) {
    if rt == nil { return }
    if rt.ctx != nil && (rt.surfaceless || rt.surface != nil) {
        current := save_context(rt.display)
        if err := enter(&current, rt.ctx, rt.surface); err == nil {
            for &chain in rt.chains { if chain != nil { cleanup_error(check(libra_gl_filter_chain_free(&chain))) } }
            gl.Flush()
        } else { s := message(err); glib.g_log(nil, 8, "WaylandShader cannot release shader objects: %.*s", i32(len(s)), raw_data(s)) }
        cleanup_error(restore(&current))
    }
    if rt.ctx != nil { DestroyContext(rt.display, rt.ctx) }
    if rt.surface != nil { DestroySurface(rt.display, rt.surface) }
    for p in rt.parameters { delete(p.name); delete(p.description) }
    for name in rt.names { delete(name) }
    delete(rt.parameters); delete(rt.names); delete(rt.keys); delete(rt.chains)
    free(rt)
}
