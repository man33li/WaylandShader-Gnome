package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "core:thread"
import gl "vendor:OpenGL"
import image "vendor:stb/image"
import sr ".."

require :: proc(ok: bool, message: string) { if !ok { fmt.eprintln(message); os.exit(1) } }
require_error :: proc(err: sr.Error) { if s, bad := err.?; bad { require(false, s) } }

make_texture :: proc(source: bool) -> u32 {
    texture: u32
    gl.GenTextures(1, &texture)
    gl.BindTexture(gl.TEXTURE_2D, texture)
    gl.TexStorage2D(gl.TEXTURE_2D, 7 if source else 1, gl.RGBA16F, 64, 32)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0)
    if source {
        pixels: [64*32*4]f32
        for i in 0..<64*32 { pixels[i*4+0] = .25; pixels[i*4+1] = .5; pixels[i*4+2] = .75; pixels[i*4+3] = 1 }
        gl.TexSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 64, 32, gl.RGBA, gl.FLOAT, &pixels[0])
    }
    return texture
}
Job :: struct { display: sr.Display, host: sr.Context, path: string, keys: []uintptr, result: ^sr.Runtime, error: string }
load_worker :: proc(job: ^Job) { runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(); job.result, job.error = sr.load(job.display, job.host, job.path, job.keys, nil) }
worker_load :: proc(display: sr.Display, host: sr.Context, path: string, keys: []uintptr) -> ^sr.Runtime {
    job := Job{display=display, host=host, path=path, keys=keys}
    worker := thread.create_and_start_with_poly_data(&job, load_worker)
    require(worker != nil, "Cannot start shader loading worker")
    thread.join(worker); thread.destroy(worker)
    require(job.result != nil, job.error)
    return job.result
}
worker_reject :: proc(display: sr.Display,host: sr.Context,path: string,keys: []uintptr) {
    job:=Job{display=display,host=host,path=path,keys=keys}
    worker:=thread.create_and_start_with_poly_data(&job,load_worker)
    require(worker!=nil,"Cannot start failing shader loading worker")
    thread.join(worker); thread.destroy(worker)
    require(job.result==nil,"Broken shader unexpectedly compiled")
    defer delete(job.error)
    require(strings.has_prefix(job.error,fmt.tprintf("Could not compile '%s': ",path)),"Failed load error did not survive its worker temporary guard")
    require(sr.GetCurrentContext()==host,"Failed load changed the host context")
}
check_frame :: proc(rt: ^sr.Runtime, host: sr.Context, source, destination, readback: u32, key: uintptr, number: u64, clear: bool, expected: [3]f32) {
    frame := sr.Frame{number=number, source=source, destination=destination, format=gl.RGBA16F, width=64, height=32, fps=60, elapsed_ms=17, clear_history=clear}
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    gl.Viewport(7, 9, 13, 15)
    require_error(sr.render(rt, key, &frame))
    require(sr.GetCurrentContext() == host, "Host EGL context was not restored")
    viewport: [4]i32
    gl.GetIntegerv(gl.VIEWPORT, &viewport[0])
    require(viewport == [4]i32{7,9,13,15}, "Shader rendering changed the host viewport")
    gl.BindFramebuffer(gl.FRAMEBUFFER, readback)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, destination, 0)
    require(gl.CheckFramebufferStatus(gl.FRAMEBUFFER) == gl.FRAMEBUFFER_COMPLETE, "Readback framebuffer is incomplete")
    pixel: [4]f32
    gl.ReadPixels(32, 16, 1, 1, gl.RGBA, gl.FLOAT, &pixel[0])
    require(gl.GetError() == gl.NO_ERROR, "OpenGL rendering/readback failed")
    for value, i in expected { require(!math.is_nan(pixel[i]) && !math.is_inf(pixel[i]) && abs(pixel[i]-value) < .003, fmt.tprintf("output %d frame %d channel %d: got %g expected %g", key, number, i, pixel[i], value)) }
}
exercise :: proc(display: sr.Display, config: sr.Config, robust: bool, preset, base_preset, broken_preset: string) {
    attributes := [?]i32{sr.CONTEXT_MAJOR_VERSION,3,sr.CONTEXT_MINOR_VERSION,3,sr.CONTEXT_OPENGL_PROFILE_MASK,sr.CONTEXT_OPENGL_CORE_PROFILE_BIT,sr.CONTEXT_FLAGS,sr.CONTEXT_OPENGL_ROBUST_ACCESS_BIT if robust else 0,sr.CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY,sr.LOSE_CONTEXT_ON_RESET if robust else sr.NO_RESET_NOTIFICATION,sr.NONE}
    host := sr.CreateContext(display, config, nil, &attributes[0])
    dimensions := [?]i32{sr.WIDTH,1,sr.HEIGHT,1,sr.NONE}
    surface := sr.CreatePbufferSurface(display, config, &dimensions[0])
    require(host != nil && surface != nil && bool(sr.MakeCurrent(display,surface,surface,host)), "Cannot create the required host OpenGL context")
    defer { sr.MakeCurrent(display,nil,nil,nil); sr.DestroyContext(display,host); sr.DestroySurface(display,surface) }
    sr.ensure_gl_loaded()
    fmt.printf("GL %s; robust=%v\n", string(gl.GetString(gl.VERSION)), robust)
    source := make_texture(true)
    destination := make_texture(false)
    defer gl.DeleteTextures(1, &source)
    defer gl.DeleteTextures(1, &destination)
    readback: u32
    gl.GenFramebuffers(1, &readback)
    defer gl.DeleteFramebuffers(1, &readback)
    keys := [?]uintptr{11,22}
    for cycle in 0..<2 {
        rt := worker_load(display, host, preset, keys[:])
        defer sr.destroy(rt)
        check_frame(rt,host,source,destination,readback,11,0,true,{.12549,.25,.125})
        check_frame(rt,host,source,destination,readback,11,1,false,{.12549,.75,.25})
        check_frame(rt,host,source,destination,readback,11,2,false,{.12549,.75,.375})
        check_frame(rt,host,source,destination,readback,22,0,true,{.12549,.25,.125})
        check_frame(rt,host,source,destination,readback,11,3,true,{.12549,.25,.125})
        require(sr.set_parameter(rt,"MISSING",1) != nil, "Unknown parameter accepted")
        require(sr.set_parameter(rt,"GAIN",3) != nil, "Out-of-range parameter accepted")
        require_error(sr.set_parameter(rt,"GAIN",.5))
        check_frame(rt,host,source,destination,readback,11,4,false,{.062745,.375,.125})
        check_frame(rt,host,source,destination,readback,22,1,false,{.062745,.375,.125})
        require_error(sr.set_parameter(rt,"GAIN",.1))
        check_frame(rt,host,source,destination,readback,11,5,true,{.012549,.025,.0125})
        worker_reject(display,host,broken_preset,keys[:])
        check_frame(rt,host,source,destination,readback,11,6,true,{.012549,.025,.0125})
        frame := sr.Frame{number=7, source=source, destination=destination, format=gl.RGBA16F,width=64,height=32,fps=60,elapsed_ms=17}
        require_error(sr.render(rt,11,&frame))
        tracking: mem.Tracking_Allocator
        mem.tracking_allocator_init(&tracking, context.allocator)
        old_heap, old_temp := context.allocator, context.temp_allocator
        context.allocator = mem.tracking_allocator(&tracking)
        context.temp_allocator = context.allocator
        before := tracking.total_allocation_count
        for _ in 0..<100 { frame.number += 1; require_error(sr.render(rt,11,&frame)) }
        allocations := tracking.total_allocation_count-before
        context.allocator = old_heap; context.temp_allocator = old_temp
        mem.tracking_allocator_destroy(&tracking)
        require(allocations == 0, "Shader render allocated Odin memory after warmup")
        fmt.printf("cycle %d passed\n",cycle)
    }
    fresh := make_texture(true)
    defer gl.DeleteTextures(1,&fresh)
    rt := worker_load(display,host,base_preset,keys[:1])
    defer sr.destroy(rt)
    check_frame(rt,host,fresh,destination,readback,11,0,true,{.25,.5,.75})
}
main :: proc() {
    require(len(os.args) == 2,"Pass the shader fixture directory")
    if !sr.has_extension(nil,"EGL_EXT_platform_base") || !sr.has_extension(nil,"EGL_MESA_platform_surfaceless") { fmt.eprintln("These real-GL regressions require Mesa surfaceless EGL."); os.exit(77) }
    directory, de := os.make_directory_temp("","waylandshader-*",context.allocator)
    require(de == nil,"Cannot create the isolated fixture directory")
    defer { os.remove_all(directory); delete(directory) }
    for file in ([?]string{"temporal.slangp","temporal.slang","finish.slang"}) {
        contents, err := os.read_entire_file(fmt.tprintf("%s/%s",os.args[1],file),context.temp_allocator)
        require(err == nil,"Cannot read shader fixture")
        require(os.write_entire_file(fmt.tprintf("%s/%s",directory,file),contents) == nil,"Cannot copy shader fixture")
    }
    base_preset := fmt.tprintf("%s/base-level.slangp",directory)
    require(os.write_entire_file(base_preset,"shaders = 1\nshader0 = base-level.slang\nfilter_linear0 = true\nmipmap_input0 = false\n") == nil,"Cannot create base-level preset")
    shader := `#version 450
layout(std140, set = 0, binding = 0) uniform UBO { mat4 MVP; } global;
#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 uv;
void main() { gl_Position = global.MVP * Position; uv = TexCoord; }
#pragma stage fragment
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;
void main() { FragColor = textureLod(Source, uv, 3.0); }
`
    require(os.write_entire_file(fmt.tprintf("%s/base-level.slang",directory),shader) == nil,"Cannot create base-level shader")
    broken_preset:=fmt.tprintf("%s/broken.slangp",directory)
    require(os.write_entire_file(broken_preset,"shaders = 1\nshader0 = broken.slang\n")==nil,"Cannot create failing preset")
    require(os.write_entire_file(fmt.tprintf("%s/broken.slang",directory),"#version 450\nthis shader cannot compile\n")==nil,"Cannot create failing shader")
    lut := [16]u8{128,255,255,255,128,255,255,255,128,255,255,255,128,255,255,255}
    png, pe := strings.clone_to_cstring(fmt.tprintf("%s/lookup.png",directory),context.temp_allocator)
    require(pe == nil && image.write_png(png,2,2,4,&lut[0],8) != 0,"Cannot create LUT fixture")
    display := sr.GetPlatformDisplay(sr.PLATFORM_SURFACELESS_MESA,nil,nil)
    require(bool(sr.Initialize(display,nil,nil)),"EGL initialization failed")
    defer sr.Terminate(display)
    require(bool(sr.BindAPI(sr.OPENGL_API)),"Desktop OpenGL is unavailable")
    attributes := [?]i32{sr.SURFACE_TYPE,sr.PBUFFER_BIT,sr.RENDERABLE_TYPE,sr.OPENGL_BIT,sr.NONE}
    config: sr.Config
    count: i32
    require(bool(sr.ChooseConfig(display,&attributes[0],&config,1,&count)) && count>0,"No host OpenGL configuration")
    preset := fmt.tprintf("%s/temporal.slangp",directory)
    for robust in ([?]bool{false,true}) { exercise(display,config,robust,preset,base_preset,broken_preset) }
    fmt.println("Temporal isolation, resets, reloads, parameters, base-level sampling, and context sharing passed.")
}
