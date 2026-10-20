package waylandshader

import "base:runtime"
import "core:fmt"
import gl "vendor:OpenGL"
import common "../common"
import glib "../glib"
import sr "../runtime"

SNIPPET_DECL :: "uniform float wls_gamma; uniform float wls_saturation;"
SNIPPET_BODY :: "if (wls_gamma != 1.0 || wls_saturation != 1.0) {\n" +
    "  if (cogl_texel.a > 0.0) {\n" +
    "    vec3 rgb = pow(max(cogl_texel.rgb / cogl_texel.a, vec3(0.0)), vec3(1.0 / wls_gamma));\n" +
    "    vec3 linear_rgb = mix(pow((rgb + 0.055) / 1.055, vec3(2.4)), rgb / 12.92, lessThanEqual(rgb, vec3(0.04045)));\n" +
    "    float luma = dot(linear_rgb, vec3(0.2126, 0.7152, 0.0722));\n" +
    "    linear_rgb = max(mix(vec3(luma), linear_rgb, wls_saturation), vec3(0.0));\n" +
    "    rgb = mix(1.055 * pow(linear_rgb, vec3(1.0 / 2.4)) - 0.055, 12.92 * linear_rgb, lessThanEqual(linear_rgb, vec3(0.0031308)));\n" +
    "    cogl_texel.rgb = rgb * cogl_texel.a;\n" +
    "  } else { cogl_texel.rgb = vec3(0.0); }\n" + "}"

Surface :: struct { texture: ^Texture, fb: ^Framebuffer }
Resources :: struct {
    width,height: i32,
    raw,srgb,destination,final: Surface,
    to_srgb,to_target: ^Pipeline,
    target_color,working_color: ^Color_State,
    source,read_fbo,draw_fbo: u32,
    gamma_uniform,saturation_uniform: i32,
    gamma,saturation: f64,
    retained_by_runtime,target_is_srgb: bool,
}
GL_Bindings :: struct { texture,read,draw,unpack: i32, scissor,srgb: bool }
save_bindings :: proc() -> GL_Bindings {
    b:GL_Bindings
    gl.GetIntegerv(gl.TEXTURE_BINDING_2D,&b.texture); gl.GetIntegerv(gl.READ_FRAMEBUFFER_BINDING,&b.read); gl.GetIntegerv(gl.DRAW_FRAMEBUFFER_BINDING,&b.draw); gl.GetIntegerv(gl.PIXEL_UNPACK_BUFFER_BINDING,&b.unpack)
    b.scissor=bool(gl.IsEnabled(gl.SCISSOR_TEST)); b.srgb=bool(gl.IsEnabled(gl.FRAMEBUFFER_SRGB))
    return b
}
restore_bindings :: proc(b: GL_Bindings) {
    gl.BindTexture(gl.TEXTURE_2D,u32(b.texture)); gl.BindFramebuffer(gl.READ_FRAMEBUFFER,u32(b.read)); gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER,u32(b.draw)); gl.BindBuffer(gl.PIXEL_UNPACK_BUFFER,u32(b.unpack))
    if b.scissor { gl.Enable(gl.SCISSOR_TEST) } else { gl.Disable(gl.SCISSOR_TEST) }
    if b.srgb { gl.Enable(gl.FRAMEBUFFER_SRGB) } else { gl.Disable(gl.FRAMEBUFFER_SRGB) }
}
host_context :: proc(e: ^Engine) -> (sr.Current_Context,Error) {
    host:=sr.save_context(e.display)
    if e.display==nil || e.ctx==nil || host.display==e.display && host.ctx==e.ctx { return host,nil }
    host.changed=true
    if !sr.BindAPI(sr.OPENGL_API) || !sr.MakeCurrent(e.display,e.draw,e.read,e.ctx) { warn("WaylandShader",sr.restore(&host)); return host,"Unable to acquire the GNOME compositor EGL context" }
    return host,nil
}
gl_error :: proc(operation: string,code: u32) -> string { return fmt.tprintf("%s failed (GL 0x%x)",operation,code) }
cogl_error :: proc(err: ^glib.Error,fallback: string) -> Error {
    if err==nil { return fallback }
    defer glib.g_error_free(err)
    return fmt.tprintf("%s",string(err.message))
}
surface_destroy :: proc(s: ^Surface) { if s.fb!=nil { glib.g_object_unref(s.fb) }; if s.texture!=nil { glib.g_object_unref(s.texture) }; s^={} }
surface_allocate :: proc(s: ^Surface,ctx: ^Cogl_Context,width,height: i32) -> Error {
    if s.texture!=nil { return nil }
    pending:Surface
    defer surface_destroy(&pending)
    pending.texture=cogl_texture_2d_new_with_format(ctx,width,height,155)
    if pending.texture==nil { return "Out of memory" }
    cogl_texture_2d_set_auto_mipmap(pending.texture,false)
    err:^glib.Error
    if !cogl_texture_allocate(pending.texture,&err) { return cogl_error(err,"Unable to allocate stage texture") }
    pending.fb=cogl_offscreen_new_with_texture(pending.texture)
    if pending.fb==nil { return "Out of memory" }
    if !cogl_framebuffer_allocate(pending.fb,&err) { return cogl_error(err,"Unable to allocate stage framebuffer") }
    identity:=Matrix{values={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}}
    cogl_framebuffer_set_modelview_matrix(pending.fb,&identity)
    cogl_framebuffer_orthographic(pending.fb,0,0,f32(width),f32(height),-1,1)
    cogl_framebuffer_set_viewport(pending.fb,0,0,f32(width),f32(height))
    cogl_framebuffer_clear4f(pending.fb,1,0,0,0,0)
    s^=pending; pending={}
    return nil
}
surface_name :: proc(s: ^Surface) -> (u32,Error) {
    name,target:u32
    if !cogl_texture_get_gl_texture(s.texture,&name,&target) || target!=gl.TEXTURE_2D { return 0,"Cogl did not allocate a desktop GL 2D texture" }
    return name,nil
}
new_pipeline :: proc(ctx: ^Cogl_Context) -> (^Pipeline,Error) {
    p:=cogl_pipeline_new(ctx)
    if p==nil { return nil,"Out of memory" }
    err:^glib.Error
    if !cogl_pipeline_set_blend(p,"RGBA = ADD(SRC_COLOR, 0)",&err) { glib.g_object_unref(p); return nil,cogl_error(err,"Unable to configure replacement blending") }
    cogl_pipeline_set_layer_filters(p,0,9728,9728)
    cogl_pipeline_set_layer_wrap_mode(p,0,33071)
    return p,nil
}
resources_destroy :: proc(r: ^Resources) {
    if r==nil { return }
    surface_destroy(&r.raw); surface_destroy(&r.srgb); surface_destroy(&r.destination); surface_destroy(&r.final)
    if r.to_srgb!=nil { glib.g_object_unref(r.to_srgb) }; if r.to_target!=nil { glib.g_object_unref(r.to_target) }
    if r.target_color!=nil { glib.g_object_unref(r.target_color) }; if r.working_color!=nil { glib.g_object_unref(r.working_color) }
    if r.source!=0 { gl.DeleteTextures(1,&r.source) }; if r.read_fbo!=0 { gl.DeleteFramebuffers(1,&r.read_fbo) }; if r.draw_fbo!=0 { gl.DeleteFramebuffers(1,&r.draw_fbo) }
    free(r)
}
configure_color :: proc(r: ^Resources,target,srgb: ^Color_State) -> Error {
    if r.target_color==target && r.to_srgb!=nil && r.to_target!=nil { return nil }
    if r.to_srgb!=nil { glib.g_object_unref(r.to_srgb); r.to_srgb=nil }; if r.to_target!=nil { glib.g_object_unref(r.to_target); r.to_target=nil }
    if r.target_color!=nil { glib.g_object_unref(r.target_color) }; r.target_color=cast(^Color_State)glib.g_object_ref(target)
    if r.working_color!=nil { glib.g_object_unref(r.working_color); r.working_color=nil }
    luminance:^Luminance
    if glib.g_type_check_instance_is_a(target,clutter_color_state_params_get_type()) { luminance=clutter_color_state_params_get_luminance(target) }
    if luminance!=nil && luminance.mastering_max>luminance.reference {
        working:=clutter_color_state_params_get_luminance(srgb)
        ctx:rawptr
        glib.g_object_get(srgb,"context",&ctx,rawptr(nil))
        r.working_color=clutter_color_state_params_new_full(ctx,0,0,nil,-1,working.minimum,working.maximum,working.reference,working.reference*luminance.mastering_max/luminance.reference)
        glib.g_object_unref(ctx)
    } else { r.working_color=cast(^Color_State)glib.g_object_ref(srgb) }
    if r.working_color==nil { return "Unable to create the shader working color state" }
    r.target_is_srgb=bool(clutter_color_state_equals(target,r.working_color))
    ctx:=cogl_framebuffer_get_context(r.raw.fb)
    err:Error
    r.to_srgb,err=new_pipeline(ctx)
    if err!=nil { return err }
    clutter_color_state_add_pipeline_transform(target,r.working_color,r.to_srgb,0)
    r.to_target,err=new_pipeline(ctx)
    if err!=nil { return err }
    adjustment:=cogl_snippet_new(6145,SNIPPET_DECL,SNIPPET_BODY)
    if adjustment==nil { return "Out of memory" }
    cogl_pipeline_add_layer_snippet(r.to_target,0,adjustment); glib.g_object_unref(adjustment)
    clutter_color_state_add_pipeline_transform(r.working_color,target,r.to_target,0)
    r.gamma_uniform=cogl_pipeline_get_uniform_location(r.to_target,"wls_gamma"); r.saturation_uniform=cogl_pipeline_get_uniform_location(r.to_target,"wls_saturation")
    r.gamma=-1; r.saturation=-1
    return nil
}
copy_shader_source :: proc(r: ^Resources,source: ^Surface) -> Error {
    cogl_framebuffer_flush(source.fb)
    bindings:=save_bindings(); defer restore_bindings(bindings)
    gl.Disable(gl.SCISSOR_TEST); gl.Disable(gl.FRAMEBUFFER_SRGB)
    if r.source==0 {
        gl.GenTextures(1,&r.source); gl.BindTexture(gl.TEXTURE_2D,r.source); gl.BindBuffer(gl.PIXEL_UNPACK_BUFFER,0)
        level:i32=0
        for w,h:=r.width,r.height; ; w,h=max(1,w/2),max(1,h/2) { gl.TexImage2D(gl.TEXTURE_2D,level,gl.RGBA16F,w,h,0,gl.RGBA,gl.HALF_FLOAT,nil); level+=1; if w==1 && h==1 { break } }
        gl.TexParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR); gl.TexParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR)
        gl.TexParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE); gl.TexParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE)
        gl.GenFramebuffers(1,&r.read_fbo); gl.GenFramebuffers(1,&r.draw_fbo)
    }
    name,err:=surface_name(source)
    if err!=nil { return err }
    gl.BindFramebuffer(gl.READ_FRAMEBUFFER,r.read_fbo); gl.FramebufferTexture2D(gl.READ_FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,name,0); gl.ReadBuffer(gl.COLOR_ATTACHMENT0)
    gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER,r.draw_fbo); gl.FramebufferTexture2D(gl.DRAW_FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,r.source,0); gl.DrawBuffer(gl.COLOR_ATTACHMENT0)
    if gl.CheckFramebufferStatus(gl.READ_FRAMEBUFFER)!=gl.FRAMEBUFFER_COMPLETE || gl.CheckFramebufferStatus(gl.DRAW_FRAMEBUFFER)!=gl.FRAMEBUFFER_COMPLETE { return "Incomplete shader source copy framebuffer" }
    gl.BlitFramebuffer(0,0,r.width,r.height,0,0,r.width,r.height,gl.COLOR_BUFFER_BIT,gl.NEAREST)
    gl.BindTexture(gl.TEXTURE_2D,r.source); gl.TexParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAX_LEVEL,0)
    if code:=gl.GetError(); code!=gl.NO_ERROR { return gl_error("Shader source GPU copy",code) }
    return nil
}
render_surface :: proc(fb: ^Framebuffer,p: ^Pipeline,texture: ^Texture,width,height: i32) -> Error {
    cogl_pipeline_set_layer_texture(p,0,texture)
    cogl_framebuffer_draw_textured_rectangle(fb,p,0,0,f32(width),f32(height),0,0,1,1)
    cogl_framebuffer_flush(fb)
    if code:=gl.GetError(); code!=gl.NO_ERROR { return gl_error("Stage color conversion",code) }
    return nil
}
frame_timing :: proc(c: ^Frame_Clock,count,now: i64,refresh: f32) -> (render: bool,fps: f32,elapsed_ms: u32,number: u64) {
    fps=refresh
    if fps==0 {
        if c.previous_time>0 && now>c.previous_time { fps=f32(1000000.0/f64(now-c.previous_time)) }
        else { c.previous_time=now; return false,0,0,0 }
    }
    if c.first_frame<0 { c.first_frame=count }
    elapsed:i64=0
    if c.previous_time>0 { elapsed=max(i64(0),(now-c.previous_time)/1000) }
    return true,fps,u32(min(elapsed,i64(0xffffffff))),u64(max(i64(0),count-c.first_frame))
}
select_output :: proc(views: []Output_View,view: ^Stage_View,frame: i64) -> int { for v,i in views { if v.view==view { return i if v.expanded_frame==frame else -1 } }; return -1 }
continue_scene :: proc(e: ^Engine,pc: ^Paint_Context,continued: ^bool) { if actor:=clutter_actor_meta_get_actor(cast(^Actor_Meta)e.self); actor!=nil { continued^=true; clutter_actor_continue_paint(actor,pc) } }
renderer_failure :: proc(e: ^Engine,err: Error) { e.renderer_failed=true; e.loading=false; set_str(&e.pending,""); e.generation+=1; fail(e,error_message(err)) }
before_paint :: proc "c" (stage: ^Actor,view: ^Stage_View,frame: ^Frame,data: rawptr) {
    context=boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    e:=cast(^Engine)data
    if e.stopped || e.renderer_failed { return }
    if err:=discover(e,view); err!=nil { renderer_failure(e,err); return }
    for &v,i in e.views { if v.view==view && (shader(e,e.outputs[i])||color(e,e.outputs[i])) { clutter_stage_view_add_redraw_clip(view,nil); v.expanded_frame=clutter_frame_get_count(frame); break } }
}
engine_paint :: proc(e: ^Engine,pc: ^Paint_Context,flags: u32,continued: ^bool) -> Error {
    view:=clutter_paint_context_get_stage_view(pc); frame:=clutter_paint_context_get_frame(pc)
    if e.stopped || e.renderer_failed || view==nil || frame==nil || flags&2!=0 { continue_scene(e,pc,continued); return nil }
    target:=clutter_paint_context_get_framebuffer(pc)
    if target!=clutter_stage_view_get_framebuffer(view) { continue_scene(e,pc,continued); return nil }
    captured,context_error:=capture_context(e)
    if context_error!=nil { return context_error }; if !captured { return "GNOME has no current desktop OpenGL EGL context" }
    index:=select_output(e.views[:],view,clutter_frame_get_count(frame))
    if index<0 || !(shader(e,e.outputs[index])||color(e,e.outputs[index])) { continue_scene(e,pc,continued); return nil }
    o:=e.outputs[index]
    target_color:=clutter_paint_context_get_target_color_state(pc)
    width,height:=cogl_framebuffer_get_width(target),cogl_framebuffer_get_height(target)
    if width<=0 || height<=0 || target_color==nil { return "Invalid stage framebuffer or target color state" }
    if err:=paint_output(e,o,view,frame,pc,target,target_color,width,height,continued); err!=nil { if allocation_error:=set_str(&o.failure,error_message(err)); allocation_error!=nil { fail(e,error_message(allocation_error)) } else { fail(e,o.failure) }; if !continued^ { continue_scene(e,pc,continued) } }
    return nil
}
paint_output :: proc(e: ^Engine,o: ^Output,view: ^Stage_View,frame: ^Frame,pc: ^Paint_Context,target: ^Framebuffer,target_color: ^Color_State,width,height: i32,continued: ^bool) -> (result: Error) {
    captured,wrote_target:=false,false
    defer if result!=nil && captured && wrote_target {
        restore_error:^glib.Error
        if !cogl_framebuffer_blit(o.resources.raw.fb,target,0,0,0,0,width,height,&restore_error) { warn("WaylandShader raw-scene restoration",cogl_error(restore_error,"GPU blit failed")) }
    }
    if o.resources==nil || o.resources.width!=width || o.resources.height!=height {
        r,ae:=new(Resources)
        if ae!=nil { return "Out of memory" }
        r.width=width; r.height=height
        if err:=surface_allocate(&r.raw,cogl_framebuffer_get_context(target),width,height); err!=nil { resources_destroy(r); return err }
        if o.resources!=nil && o.resources.retained_by_runtime { resources_destroy(o.retired); o.retired=o.resources }
        else { resources_destroy(o.resources) }
        o.resources=r; reset_clock(o)
    }
    r:=o.resources
    if err:=configure_color(r,target_color,e.srgb); err!=nil { return err }
    cogl_framebuffer_clear4f(target,1,0,0,0,0)
    continue_scene(e,pc,continued)
    cogl_context_flush(cogl_framebuffer_get_context(target))
    copy_error:^glib.Error
    if !cogl_framebuffer_blit(target,r.raw.fb,0,0,0,0,width,height,&copy_error) { return cogl_error(copy_error,"Unable to copy the current stage scene") }
    captured=true
    ctx:=cogl_framebuffer_get_context(target)
    processed:=&r.raw
    if !r.target_is_srgb {
        if err:=surface_allocate(&r.srgb,ctx,width,height); err!=nil { return err }
        clutter_color_state_update_uniforms(target_color,r.working_color,r.to_srgb)
        if err:=render_surface(r.srgb.fb,r.to_srgb,r.raw.texture,width,height); err!=nil { return err }
        processed=&r.srgb
    }
    render_shader:=shader(e,o)
    now:i64
    fps:f32
    elapsed:u32
    number:u64
    if render_shader {
        if !clutter_frame_get_expected_presentation_time(frame,&now) { now=glib.g_get_monotonic_time() }
        render_shader,fps,elapsed,number=frame_timing(&o.clock,clutter_frame_get_count(frame),now,clutter_frame_clock_get_refresh_rate(clutter_stage_view_get_frame_clock(view)))
    }
    if render_shader {
        if err:=surface_allocate(&r.destination,ctx,width,height); err!=nil { return err }
        if err:=copy_shader_source(r,processed); err!=nil { return err }
        destination,destination_error:=surface_name(&r.destination)
        if destination_error!=nil { return destination_error }
        input:=sr.Frame{number=number,source=r.source,destination=destination,format=gl.RGBA16F,width=width,height=height,fps=fps,elapsed_ms=elapsed,clear_history=o.clock.clear_history}
        r.retained_by_runtime=true
        if err:=sr.render(e.runtime,o.key,&input); err!=nil { return err }
        old:i32
        gl.GetIntegerv(gl.TEXTURE_BINDING_2D,&old); gl.BindTexture(gl.TEXTURE_2D,destination); gl.BindTexture(gl.TEXTURE_2D,u32(old))
        o.clock.previous_time=now; o.clock.clear_history=false
        resources_destroy(o.retired); o.retired=nil; processed=&r.destination
    } else if e.runtime==nil { resources_destroy(o.retired); o.retired=nil }
    if !r.target_is_srgb || common.adjusts_color(o.settings) {
        if err:=surface_allocate(&r.final,ctx,width,height); err!=nil { return err }
        gamma:=o.settings.gamma if common.adjusts_color(o.settings) else 1.0
        saturation:=o.settings.saturation if common.adjusts_color(o.settings) else 1.0
        if gamma!=r.gamma { cogl_pipeline_set_uniform_1f(r.to_target,r.gamma_uniform,f32(gamma)); r.gamma=gamma }
        if saturation!=r.saturation { cogl_pipeline_set_uniform_1f(r.to_target,r.saturation_uniform,f32(saturation)); r.saturation=saturation }
        clutter_color_state_update_uniforms(r.working_color,target_color,r.to_target)
        if err:=render_surface(r.final.fb,r.to_target,processed.texture,width,height); err!=nil { return err }
        processed=&r.final
    }
    wrote_target=true
    present_error:^glib.Error
    if !cogl_framebuffer_blit(processed.fb,target,0,0,0,0,width,height,&present_error) { return cogl_error(present_error,"Unable to present the processed stage frame") }
    if code:=gl.GetError(); code!=gl.NO_ERROR { return gl_error("Stage presentation",code) }
    return nil
}
