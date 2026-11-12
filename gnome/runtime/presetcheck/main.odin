package main

// Arbitrary user-preset integration check, not the fixed-fixture regression or a compositor.
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:os"
import "core:thread"
import gl "vendor:OpenGL"
import sr ".."

W :: 128
H :: 72
FRAMES :: 8
require :: proc(ok: bool, message: string) { if !ok { fmt.eprintln(message); os.exit(1) } }
require_error :: proc(err: sr.Error) { if text, bad := err.?; bad { require(false, text) } }
source_value :: proc(x, y, channel: int) -> f32 {
    switch channel {
    case 0: return .125 + .75*f32(x)/f32(W-1)
    case 1: return .125 + .75*f32(y)/f32(H-1)
    case 2: return .25 if (x/16+y/12)%2 == 0 else .75
    case: return 1
    }
}
texture :: proc(source: bool) -> u32 {
    id: u32
    gl.GenTextures(1, &id); gl.BindTexture(gl.TEXTURE_2D, id)
    gl.TexStorage2D(gl.TEXTURE_2D, 8 if source else 1, gl.RGBA16F, W, H)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0)
    if source {
        data: [W*H*4]f32
        for y in 0..<H { for x in 0..<W { for channel in 0..<4 { data[(y*W+x)*4+channel] = source_value(x,y,channel) } } }
        gl.TexSubImage2D(gl.TEXTURE_2D, 0, 0, 0, W, H, gl.RGBA, gl.FLOAT, &data[0])
    }
    return id
}
framebuffer :: proc(id: u32) -> u32 {
    fb: u32
    gl.GenFramebuffers(1, &fb); gl.BindFramebuffer(gl.FRAMEBUFFER, fb)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, id, 0)
    require(gl.CheckFramebufferStatus(gl.FRAMEBUFFER) == gl.FRAMEBUFFER_COMPLETE, "incomplete framebuffer")
    return fb
}
Job :: struct { display: sr.Display, host: sr.Context, path: string, result: ^sr.Runtime, error: string }
load_worker :: proc(job: ^Job) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    keys := [?]uintptr{11}
    job.result, job.error = sr.load(job.display, job.host, job.path, keys[:], nil)
}
load :: proc(display: sr.Display, host: sr.Context, path: string) -> Job {
    job := Job{display=display,host=host,path=path}
    worker := thread.create_and_start_with_poly_data(&job, load_worker)
    require(worker != nil, "cannot start preset worker")
    thread.join(worker); thread.destroy(worker)
    return job
}
restore_check :: proc(host: sr.Context) {
    require(sr.GetCurrentContext() == host, "host context was not restored")
    viewport: [4]i32
    gl.GetIntegerv(gl.VIEWPORT, &viewport[0])
    require(viewport == [4]i32{7,9,13,15} && gl.GetError() == gl.NO_ERROR, "host viewport changed/GL error")
}
main :: proc() {
    require(len(os.args) == 4 && (os.args[2] == "identity" || os.args[2] == "capture"), "usage: presetcheck ABSOLUTE.slangp identity|capture OUTPUT.ppm")
    identity := os.args[2] == "identity"
    require(sr.has_extension(nil, "EGL_EXT_platform_base") && sr.has_extension(nil, "EGL_MESA_platform_surfaceless"), "surfaceless EGL unavailable")
    display := sr.GetPlatformDisplay(sr.PLATFORM_SURFACELESS_MESA, nil, nil)
    require(bool(sr.Initialize(display,nil,nil)) && bool(sr.BindAPI(sr.OPENGL_API)), "cannot initialize EGL")
    attrs := [?]i32{sr.SURFACE_TYPE,sr.PBUFFER_BIT,sr.RENDERABLE_TYPE,sr.OPENGL_BIT,sr.NONE}
    config: sr.Config
    count: i32
    require(bool(sr.ChooseConfig(display,&attrs[0],&config,1,&count)) && count > 0, "no EGL config")
    ctx_attrs := [?]i32{sr.CONTEXT_MAJOR_VERSION,3,sr.CONTEXT_MINOR_VERSION,3,sr.CONTEXT_OPENGL_PROFILE_MASK,sr.CONTEXT_OPENGL_CORE_PROFILE_BIT,sr.NONE}
    host := sr.CreateContext(display,config,nil,&ctx_attrs[0])
    surface_attrs := [?]i32{sr.WIDTH,1,sr.HEIGHT,1,sr.NONE}
    surface := sr.CreatePbufferSurface(display,config,&surface_attrs[0])
    require(host != nil && surface != nil && bool(sr.MakeCurrent(display,surface,surface,host)), "cannot create host EGL context")
    sr.ensure_gl_loaded()
    fmt.printf("GL\t%s\t%s\t%s\nPRESET\t%s\nSETTINGS\t%d\t%d\t%d\n",string(gl.GetString(gl.VERSION)),string(gl.GetString(gl.VENDOR)),string(gl.GetString(gl.RENDERER)),os.args[1],W,H,FRAMES)
    source := texture(true)
    destination := texture(false)
    fb := framebuffer(destination)
    job := load(display,host,os.args[1])
    require(job.result != nil, job.error)
    rt := job.result
    passes: u32
    require_error(sr.check(sr.libra_gl_filter_chain_get_active_pass_count(&rt.chains[0],&passes)))
    fmt.printf("LOADED\t%d\t%d\n",passes,len(rt.parameters))
    for parameter in rt.parameters { fmt.printf("PARAM\t%s\t%g\t%g\t%g\n",parameter.name,parameter.minimum,parameter.maximum,parameter.value) }
    frame := sr.Frame{source=source,destination=destination,format=gl.RGBA16F,width=W,height=H,fps=60,elapsed_ms=17,clear_history=true}
    data: [W*H*4]f32
    for number in 0..<FRAMES {
        gl.BindFramebuffer(gl.FRAMEBUFFER,fb)
        gl.ClearColor(1,0,1,0); gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.BindFramebuffer(gl.FRAMEBUFFER,0); gl.Viewport(7,9,13,15)
        if number == 1 && identity {
            rejected := load(display,host,fmt.tprintf("%s.missing-presetcheck",os.args[1]))
            require(rejected.result == nil && len(rejected.error) > 0, "missing preset was not rejected")
            fmt.printf("REJECTED\t%s\n",rejected.error)
            delete(rejected.error)
            restore_check(host)
        }
        frame.number = u64(number)
        require_error(sr.render(rt,11,&frame)); gl.Finish(); restore_check(host)
        gl.BindFramebuffer(gl.FRAMEBUFFER,fb)
        gl.ReadPixels(0,0,W,H,gl.RGBA,gl.FLOAT,&data[0])
        require(gl.GetError() == gl.NO_ERROR, "readback GL error")
        low := data[0]
        high := data[0]
        total: f64
        maximum_error: f32
        for value,index in data {
            require(!math.is_nan(value) && !math.is_inf(value), "nonfinite pixel")
            low = min(low,value); high = max(high,value); total += f64(value)
            pixel := index/4
            maximum_error = max(maximum_error,abs(value-source_value(pixel%W,pixel/W,index%4)))
        }
        if identity { require(maximum_error < .003, "nearest spatial identity oracle failed") }
        fmt.printf("FRAME\t%d\t%g\t%g\t%g\t%g\n",number,low,high,total/f64(len(data)),maximum_error)
        frame.clear_history = false
    }
    // PPM is a deliberately SDR-clamped preview, not HDR or artistic-fidelity evidence.
    header := fmt.tprintf("P6\n%d %d\n255\n",W,H)
    image := make([]u8,len(header)+W*H*3)
    for i in 0..<len(header) { image[i] = header[i] }
    for y in 0..<H { for x in 0..<W { for channel in 0..<3 {
        image[len(header)+(y*W+x)*3+channel] = u8(clamp(data[((H-1-y)*W+x)*4+channel],0,1)*255+.5)
    } } }
    require(os.write_entire_file(os.args[3],image) == nil, "cannot write preview")
    delete(image)
    sr.destroy(rt); gl.Finish()
    require(gl.GetError() == gl.NO_ERROR, "runtime teardown GL error")
    gl.DeleteFramebuffers(1,&fb); gl.DeleteTextures(1,&source); gl.DeleteTextures(1,&destination)
    require(bool(sr.MakeCurrent(display,nil,nil,nil)), "cannot unbind host")
    require(bool(sr.DestroyContext(display,host)) && bool(sr.DestroySurface(display,surface)) && bool(sr.Terminate(display)), "EGL teardown failed")
    fmt.println("SUCCESS\t8\tCLEAN")
}
