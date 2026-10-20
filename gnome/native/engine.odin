package waylandshader

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import "core:thread"
import common "../common"
import glib "../glib"
import sr "../runtime"

Output_View :: struct { view: ^Stage_View, expanded_frame: i64 }
Frame_Clock :: struct { previous_time, first_frame: i64, clear_history: bool }
#assert(size_of(Output_View)==16 && size_of(Frame_Clock)==24)
Output :: struct {
    engine: ^Engine, key: uintptr,
    view: ^Stage_View,
    timeline: ^Timeline, destroy_handler: c.ulong,
    resources, retired: ^Resources,
    layout: Mtk_Rectangle, scale: f64,
    settings: common.Output_Settings, clock: Frame_Clock,
    id,name,failure: string,
}
Engine :: struct {
    self: ^Effect, owner: ^glib.GThread, main_ctx: ^glib.GMainContext,
    stage: ^Actor, backend: ^Meta_Backend, srgb: ^Color_State,
    before_paint_handler,purge_handler: c.ulong, status_source,work_source: u32,
    completion: ^glib.GSource, worker: ^thread.Thread, job: ^Load_Job,
    runtime: ^sr.Runtime, last_parameters: [dynamic]sr.Parameter,
    outputs: [dynamic]^Output, views: [dynamic]Output_View,
    saved_outputs: map[string]common.Output_Settings, overrides: map[string]map[string]f64,
    preset,requested,error,pending,last_status: string, recent: [dynamic]string,
    display: sr.Display, ctx: sr.Context, draw,read: sr.Surface,
    generation: u64, next_key: uintptr,
    enabled,stopped,cursor_inhibited,mapping_dirty,loading,renderer_failed: bool,
}
Load_Job :: struct {
    path,error: string, overrides: map[string]f64, keys: []uintptr, generation: u64, result: ^sr.Runtime,
    display: sr.Display, ctx: sr.Context, completion: ^glib.GSource, main_ctx: ^glib.GMainContext,
}

set_str :: proc(destination: ^string, value: string) -> Error {
    if destination^ == value { return nil }
    copied,err:=strings.clone(value)
    if err!=nil { return "Out of memory" }
    delete(destination^); destination^=copied
    return nil
}
set_map :: proc(m: ^map[string]$T, key: string, value: T) -> Error {
    if _,exists:=m^[key]; exists { m^[key]=value; return nil }
    copied,err:=strings.clone(key)
    if err!=nil { return "Out of memory" }
    if map_insert(m,copied,value)==nil { delete(copied); return "Out of memory" }
    return nil
}
error_message :: proc(err: Error) -> string { if s,ok:=err.?; ok { return s }; return "" }
warn :: proc(prefix: cstring, err: Error) { if s,ok:=err.?; ok { glib.g_log(nil,16,"%s: %.*s",prefix,i32(len(s)),raw_data(s)) } }
engine_check :: proc(e: ^Engine) -> Error {
    if e.owner!=glib.g_thread_self() { return "Native effect methods require the compositor main thread" }
    if e.stopped { return "The native effect has shut down" }
    return nil
}
get_engine :: proc(self: ^Effect) -> (^Engine,Error) {
    if self==nil || !glib.g_type_check_instance_is_a(self,wayland_shader_effect_get_type()) || self.engine==nil { return nil,"Invalid native effect" }
    if err:=engine_check(self.engine); err!=nil { return nil,err }
    return self.engine,nil
}
shader :: proc(e: ^Engine,o: ^Output) -> bool { return !e.stopped && !e.renderer_failed && e.enabled && e.stage!=nil && e.runtime!=nil && o.view!=nil && len(o.failure)==0 && o.settings.shader_enabled }
color :: proc(e: ^Engine,o: ^Output) -> bool { return !e.stopped && !e.renderer_failed && e.ctx!=nil && e.enabled && e.stage!=nil && o.view!=nil && len(o.failure)==0 && common.adjusts_color(o.settings) }
active :: proc(e: ^Engine) -> bool { for o in e.outputs { if shader(e,o)||color(e,o) { return true } }; return false }
find_output :: proc(e: ^Engine,id: string) -> (^Output,Error) { for o in e.outputs { if o.id==id { return o,nil } }; return nil,fmt.tprintf("Unknown active output: %s",id) }

notify :: proc(e: ^Engine) {
    if e.status_source!=0 || e.stopped { return }
    source:=glib.g_idle_source_new()
    if source==nil { warn("WaylandShader status","Out of memory"); return }
    glib.g_source_set_callback(source,status_idle,e,nil)
    e.status_source=glib.g_source_attach(source,e.main_ctx)
    glib.g_source_unref(source)
}
status_idle :: proc "c" (data: rawptr) -> b32 {
    context=boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    e:=cast(^Engine)data
    e.status_source=0
    self:=e.self
    glib.g_object_ref(self)
    defer glib.g_object_unref(self)
    value,err:=status_json(e)
    if err!=nil { warn("WaylandShader status",err); return false }
    defer delete(value)
    if value!=e.last_status {
        if copy_err:=set_str(&e.last_status,value); copy_err!=nil { warn("WaylandShader status",copy_err); return false }
        cvalue,ae:=strings.clone_to_cstring(value,context.temp_allocator)
        if ae==nil { glib.g_signal_emit(self,status_signal,0,cvalue) }
    }
    return false
}
redraw :: proc(e: ^Engine) {
    if e.stage==nil || e.stopped { return }
    for v in e.views { if v.view!=nil { clutter_stage_view_add_redraw_clip(v.view,nil); clutter_stage_view_schedule_update(v.view) } }
    clutter_actor_queue_redraw(e.stage)
}
queue_work :: proc(e: ^Engine) {
    if e.work_source!=0 || e.stopped { return }
    source:=glib.g_idle_source_new()
    if source==nil { warn("WaylandShader scheduling",set_str(&e.error,"Out of memory")); e.loading=false; set_str(&e.pending,""); notify(e); return }
    glib.g_source_set_callback(source,work_idle,e,nil)
    e.work_source=glib.g_source_attach(source,e.main_ctx)
    glib.g_source_unref(source)
}
work_idle :: proc "c" (data: rawptr) -> b32 {
    context=boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    e:=cast(^Engine)data
    e.work_source=0
    err:=sync_activity(e)
    if err==nil { err=start_load(e) }
    if err!=nil { warn("WaylandShader scheduling",set_str(&e.error,error_message(err))); e.loading=false; set_str(&e.pending,""); notify(e) }
    return false
}
fail :: proc(e: ^Engine,message: string) {
    if e.error!=message { if err:=set_str(&e.error,message); err!=nil { warn("WaylandShader",err) }; notify(e) }
    queue_work(e)
}
stop_timeline :: proc(o: ^Output) { if o.timeline!=nil { clutter_timeline_stop(o.timeline); glib.g_object_unref(o.timeline); o.timeline=nil } }
detach_output :: proc(o: ^Output) {
    stop_timeline(o)
    if o.view!=nil {
        if o.destroy_handler!=0 { glib.g_signal_handler_disconnect(o.view,o.destroy_handler) }
        glib.g_object_unref(o.view); o.view=nil
    }
    o.destroy_handler=0
    for &v,i in o.engine.views { if o.engine.outputs[i]==o { v={nil,-1}; break } }
}
destroy_output :: proc(o: ^Output) {
    detach_output(o)
    resources_destroy(o.resources); resources_destroy(o.retired)
    delete(o.id); delete(o.name); delete(o.failure); free(o)
}
reset_clock :: proc(o: ^Output) { o.clock={first_frame=-1,clear_history=true} }
sync_activity :: proc(e: ^Engine) -> Error {
    wants_cursor:=active(e)
    if e.backend!=nil && wants_cursor!=e.cursor_inhibited {
        if wants_cursor { meta_backend_inhibit_hw_cursor(e.backend) } else { meta_backend_uninhibit_hw_cursor(e.backend) }
        e.cursor_inhibited=wants_cursor
    }
    for o in e.outputs {
        if shader(e,o) {
            if o.timeline==nil {
                o.timeline=clutter_timeline_new_for_frame_clock(clutter_stage_view_get_frame_clock(o.view),1000)
                if o.timeline==nil { return "Out of memory" }
                clutter_timeline_set_repeat_count(o.timeline,-1)
                glib.g_signal_connect_data(o.timeline,"new-frame",rawptr(timeline_frame),o,nil,0)
                clutter_timeline_start(o.timeline)
            }
        } else { stop_timeline(o) }
    }
    return nil
}
timeline_frame :: proc "c" (timeline: ^Timeline, elapsed: i32, data: rawptr) {
    context=boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    o:=cast(^Output)data
    if o.view!=nil && shader(o.engine,o) { clutter_actor_queue_redraw_with_clip(o.engine.stage,&o.layout); clutter_stage_view_add_redraw_clip(o.view,nil); clutter_stage_view_schedule_update(o.view) }
}
map_outputs :: proc(e: ^Engine) -> Error {
    if e.backend==nil || !e.mapping_dirty { return nil }
    e.mapping_dirty=false
    manager:=meta_backend_get_monitor_manager(e.backend)
    renderer:=meta_backend_get_renderer(e.backend)
    for o,i in e.outputs {
        detach_output(o)
        if err:=set_str(&o.failure,""); err!=nil { return err }
        monitor:rawptr
        for item:=meta_monitor_manager_get_monitors(manager); item!=nil; item=item.next { if o.id==string(meta_monitor_get_connector(item.data)) { monitor=item.data; break } }
        reason:string
        if monitor==nil || !meta_monitor_is_active(monitor) { reason=fmt.tprintf("Connector has no active physical monitor: %s",o.id) }
        else {
            physical:=meta_monitor_get_outputs(monitor)
            if physical==nil || physical.next!=nil { reason=fmt.tprintf("Tiled monitors cannot be processed as independent full-frame outputs: %s",o.id) }
            else {
                crtc:=meta_output_get_assigned_crtc(physical.data)
                clones:^glib.GList
                if crtc!=nil { clones=meta_crtc_get_outputs(crtc) }
                if clones==nil || clones.next!=nil { reason=fmt.tprintf("Shared or missing CRTC prevents independent processing: %s",o.id) }
                else {
                    view:=meta_renderer_get_view_for_crtc(renderer,crtc)
                    layout:Mtk_Rectangle
                    if view!=nil { clutter_stage_view_get_layout(view,&layout) }
                    if view==nil || layout!=o.layout { reason=fmt.tprintf("Connector geometry does not match its physical stage view: %s",o.id) }
                    else { o.view=cast(^Stage_View)glib.g_object_ref(view); e.views[i]={o.view,-1}; o.destroy_handler=glib.g_signal_connect_data(view,"destroy",rawptr(view_destroyed),o,nil,0) }
                }
            }
        }
        if err:=set_str(&o.failure,reason); err!=nil { return err }
        if len(reason)>0 { if err:=set_str(&e.error,reason); err!=nil { return err } }
        reset_clock(o)
    }
    queue_work(e); notify(e)
    return nil
}
view_destroyed :: proc "c" (view: ^Stage_View,data: rawptr) {
    context=boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    o:=cast(^Output)data
    detach_output(o); o.engine.mapping_dirty=true
    if err:=reset(o.engine,true); err!=nil { fail(o.engine,error_message(err)) }
    notify(o.engine)
}
capture_context :: proc(e: ^Engine) -> (bool,Error) {
    display,ctx:=sr.GetCurrentDisplay(),sr.GetCurrentContext()
    if display==nil || ctx==nil { return false,nil }
    if e.ctx==nil {
        api:i32
        if !sr.QueryContext(display,ctx,sr.CONTEXT_CLIENT_TYPE,&api) || api!=sr.OPENGL_API || sr.QueryAPI()!=sr.OPENGL_API { return false,"GNOME must use an EGL desktop OpenGL renderer, not GLES or GLX" }
        e.display=display; e.ctx=ctx
        sr.ensure_gl_loaded()
        e.srgb=clutter_color_state_params_new(clutter_actor_get_context(e.stage),0,0)
        if e.srgb==nil { return false,"Out of memory" }
        queue_work(e); notify(e)
    }
    if display!=e.display || ctx!=e.ctx { return false,"The GNOME compositor EGL share context changed" }
    e.draw=sr.GetCurrentSurface(sr.DRAW); e.read=sr.GetCurrentSurface(sr.READ)
    return true,nil
}
discover :: proc(e: ^Engine,view: ^Stage_View) -> Error {
    if e.backend==nil {
        if !glib.g_type_check_instance_is_a(view,meta_renderer_view_get_type()) { return "This stage view is not a Mutter native physical renderer view" }
        crtc:=meta_renderer_view_get_crtc(view)
        if crtc==nil { return "This stage view has no physical or virtual CRTC" }
        e.backend=cast(^Meta_Backend)glib.g_object_ref(meta_crtc_get_backend(crtc))
    }
    _,err:=capture_context(e)
    if err!=nil { return err }
    if map_err:=map_outputs(e); map_err!=nil { return map_err }
    if active(e) && !e.cursor_inhibited { meta_backend_inhibit_hw_cursor(e.backend); e.cursor_inhibited=true }
    return nil
}
request :: proc(e: ^Engine,path: string) -> Error {
    if e.renderer_failed { return e.error if len(e.error)>0 else "The GNOME renderer is unavailable" }
    if err:=set_str(&e.requested,path); err!=nil { return err }
    if err:=set_str(&e.pending,path); err!=nil { return err }
    e.generation+=1; e.loading=true
    set_str(&e.error,""); queue_work(e); redraw(e); notify(e)
    return nil
}
job_destroy :: proc(job: ^Load_Job) {
    if job==nil { return }
    sr.destroy(job.result); delete(job.path); delete(job.error); delete(job.keys)
    for key in job.overrides { delete(key) }; delete(job.overrides); free(job)
}
new_load_job :: proc(e: ^Engine) -> (result: ^Load_Job,failure: Error) {
    job,allocation_error:=new(Load_Job)
    if allocation_error!=nil { return nil,"Out of memory" }
    defer if result==nil { job_destroy(job) }
    if copy_error:=set_str(&job.path,e.pending); copy_error!=nil { return nil,copy_error }
    if overrides,present:=e.overrides[e.pending]; present {
        for key,value in overrides { if copy_error:=set_map(&job.overrides,key,value); copy_error!=nil { return nil,copy_error } }
    }
    job.keys,allocation_error=make([]uintptr,len(e.outputs))
    if allocation_error!=nil { return nil,"Out of memory" }
    for o,i in e.outputs { job.keys[i]=o.key }
    job.generation=e.generation; job.display=e.display; job.ctx=e.ctx; job.main_ctx=e.main_ctx
    return job,nil
}
start_load :: proc(e: ^Engine) -> Error {
    if len(e.pending)==0 || e.job!=nil || e.stopped || e.renderer_failed || e.stage==nil || e.display==nil || e.ctx==nil { return nil }
    job,job_error:=new_load_job(e)
    if job_error!=nil { return job_error }
    success:=false
    defer if !success { job_destroy(job) }
    e.completion=glib.g_idle_source_new()
    if e.completion==nil { return "Out of memory" }
    job.completion=e.completion
    glib.g_source_set_callback(e.completion,complete_idle,e,nil)
    e.worker=thread.create_and_start_with_poly_data(job,compile_worker)
    if e.worker==nil { glib.g_source_unref(e.completion); e.completion=nil; return "Out of memory" }
    e.job=job; set_str(&e.pending,""); e.loading=true; success=true; notify(e)
    return nil
}
compile_worker :: proc(job: ^Load_Job) { compile_entry(job) }
compile_entry :: proc "c" (job: ^Load_Job) {
    context=boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    filesystem,encoding_error:=common.text_utf8(job.path,context.temp_allocator)
    // complete_load reports an empty failed job as Out of memory without borrowing a literal.
    if encoding_error==nil { job.result,job.error=sr.load(job.display,job.ctx,filesystem,job.keys,job.overrides) }
    glib.g_source_attach(job.completion,job.main_ctx)
}
complete_idle :: proc "c" (data: rawptr) -> b32 {
    context=boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    e:=cast(^Engine)data
    if err:=complete_load(e); err!=nil { fail(e,error_message(err)) }
    return false
}
clone_parameters :: proc(destination: ^[dynamic]sr.Parameter, source: []sr.Parameter) -> Error {
    next:[dynamic]sr.Parameter
    success:=false
    defer if !success { free_parameters(&next) }
    for p in source {
        copy:=p
        ae:runtime.Allocator_Error
        copy.name,ae=strings.clone(p.name)
        if ae!=nil { return "Out of memory" }
        copy.description,ae=strings.clone(p.description)
        if ae!=nil { delete(copy.name); return "Out of memory" }
        if _,err:=append(&next,copy); err!=nil { delete(copy.name); delete(copy.description); return "Out of memory" }
    }
    free_parameters(destination); destination^=next; success=true
    return nil
}
free_parameters :: proc(parameters: ^[dynamic]sr.Parameter) { for p in parameters^ { delete(p.name); delete(p.description) }; delete(parameters^); parameters^=nil }
complete_load :: proc(e: ^Engine) -> Error {
    thread.join(e.worker); thread.destroy(e.worker); e.worker=nil
    glib.g_source_unref(e.completion); e.completion=nil
    job:=e.job; e.job=nil
    host,host_error:=host_context(e)
    if host_error!=nil { job_destroy(job); return host_error }
    defer warn("WaylandShader",sr.restore(&host))
    defer job_destroy(job)
    if job.generation==e.generation && !e.stopped {
        if job.result!=nil {
            sr.destroy(e.runtime); e.runtime=nil
            for o in e.outputs {
                resources_destroy(o.retired); o.retired=nil
                if o.resources!=nil { o.resources.retained_by_runtime=false }
                if o.view!=nil { if len(o.failure)>0 { resources_destroy(o.resources); o.resources=nil }; set_str(&o.failure,"") }
            }
            e.runtime=job.result; job.result=nil
            if err:=set_str(&e.preset,job.path); err!=nil { return err }
            if err:=recent_prepend(e,e.preset); err!=nil { return err }
            if err:=clone_parameters(&e.last_parameters,e.runtime.parameters[:]); err!=nil { return err }
            if job.path==e.requested { set_str(&e.error,"") }
            for o in e.outputs { reset_clock(o); if len(o.failure)>0 { if err:=set_str(&e.error,o.failure); err!=nil { return err } } }
        } else {
            if err:=set_str(&e.error,job.error if len(job.error)>0 else "Out of memory"); err!=nil { return err }
            if e.runtime==nil && len(e.preset)>0 && e.preset!=job.path { if err:=set_str(&e.pending,e.preset); err!=nil { return err } }
        }
    }
    e.loading=len(e.pending)>0
    if err:=sync_activity(e); err!=nil { return err }
    if err:=start_load(e); err!=nil { return err }
    redraw(e); notify(e)
    return nil
}
reset :: proc(e: ^Engine,rebuild: bool) -> Error {
    e.generation+=1
    host,host_error:=host_context(e)
    if host_error!=nil { return host_error }
    defer warn("WaylandShader",sr.restore(&host))
    sr.destroy(e.runtime); e.runtime=nil
    for o,i in e.outputs {
        stop_timeline(o)
        resources_destroy(o.resources); o.resources=nil; resources_destroy(o.retired); o.retired=nil
        reset_clock(o); e.views[i].expanded_frame=-1
        if o.view!=nil { set_str(&o.failure,"") }
    }
    next:string
    if rebuild && !e.renderer_failed { next=e.requested if e.loading && len(e.requested)>0 else e.preset }
    if err:=set_str(&e.pending,next); err!=nil { return err }
    e.loading=!e.renderer_failed && (e.job!=nil || len(e.pending)>0)
    queue_work(e); redraw(e); notify(e)
    return nil
}
remove_source :: proc(ctx: ^glib.GMainContext,id: ^u32) { if id^!=0 { if source:=glib.g_main_context_find_source_by_id(ctx,id^); source!=nil { glib.g_source_destroy(source) }; id^=0 } }
engine_shutdown :: proc(e: ^Engine) {
    if e.stopped { return }
    e.stopped=true
    if e.stage!=nil { if e.before_paint_handler!=0 { glib.g_signal_handler_disconnect(e.stage,e.before_paint_handler) }; if e.purge_handler!=0 { glib.g_signal_handler_disconnect(e.stage,e.purge_handler) } }
    e.before_paint_handler=0; e.purge_handler=0
    remove_source(e.main_ctx,&e.status_source); remove_source(e.main_ctx,&e.work_source)
    for o in e.outputs { detach_output(o) }
    if e.backend!=nil && e.cursor_inhibited { meta_backend_uninhibit_hw_cursor(e.backend) }; e.cursor_inhibited=false
    if e.worker!=nil { thread.join(e.worker); thread.destroy(e.worker); e.worker=nil }
    if e.completion!=nil { glib.g_source_destroy(e.completion); glib.g_source_unref(e.completion); e.completion=nil }
    host,err:=host_context(e)
    if err!=nil {
        warn("WaylandShader shutdown",err)
        // The lost host context owns these GPU objects; never delete their names in another context.
        for o in e.outputs { o.resources=nil; o.retired=nil }
    }
    defer warn("WaylandShader",sr.restore(&host))
    job_destroy(e.job); e.job=nil; sr.destroy(e.runtime); e.runtime=nil
    for o in e.outputs { destroy_output(o) }; clear(&e.outputs); clear(&e.views)
    if e.srgb!=nil { glib.g_object_unref(e.srgb); e.srgb=nil }
    if e.backend!=nil { glib.g_object_unref(e.backend); e.backend=nil }
    e.stage=nil; e.loading=false; set_str(&e.pending,"")
}
engine_destroy :: proc(e: ^Engine) {
    engine_shutdown(e)
    free_parameters(&e.last_parameters)
    for o in e.outputs { destroy_output(o) }
    delete(e.outputs); delete(e.views)
    for key in e.saved_outputs { delete(key) }; delete(e.saved_outputs)
    for key,values in e.overrides { for name in values { delete(name) }; delete(values); delete(key) }; delete(e.overrides)
    for path in e.recent { delete(path) }; delete(e.recent)
    delete(e.preset); delete(e.requested); delete(e.error); delete(e.pending); delete(e.last_status)
    glib.g_main_context_unref(e.main_ctx); free(e)
}
attach :: proc(e: ^Engine,actor: ^Actor) -> Error {
    if e.stage!=nil { if e.before_paint_handler!=0 { glib.g_signal_handler_disconnect(e.stage,e.before_paint_handler) }; if e.purge_handler!=0 { glib.g_signal_handler_disconnect(e.stage,e.purge_handler) } }
    e.before_paint_handler=0; e.purge_handler=0
    if e.stage!=nil { if err:=reset(e,false); err!=nil { return err } }
    for o in e.outputs { detach_output(o) }
    if e.backend!=nil { if e.cursor_inhibited { meta_backend_uninhibit_hw_cursor(e.backend) }; glib.g_object_unref(e.backend); e.backend=nil }; e.cursor_inhibited=false
    e.stage=actor; e.mapping_dirty=true
    if actor==nil || e.stopped { return nil }
    if !glib.g_type_check_instance_is_a(actor,clutter_stage_get_type()) { return "WaylandShader must attach to the original GNOME stage" }
    e.before_paint_handler=glib.g_signal_connect_data(actor,"before-paint",rawptr(before_paint),e,nil,0)
    actor_type:=(cast(^glib.GType)(cast(^glib.GObject)actor).g_class)^
    if glib.g_signal_lookup("gl-video-memory-purged",actor_type)!=0 { e.purge_handler=glib.g_signal_connect_data(actor,"gl-video-memory-purged",rawptr(memory_purged),e,nil,0) }
    if len(e.preset)>0 { if err:=set_str(&e.pending,e.preset); err!=nil { return err }; e.loading=true }
    queue_work(e); redraw(e); notify(e)
    return nil
}
memory_purged :: proc "c" (actor: ^Actor,data: rawptr) {
    context=boundary_context()
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    e:=cast(^Engine)data
    if err:=reset(e,true); err!=nil { fail(e,error_message(err)) }
}
changed :: proc(e: ^Engine,o: ^Output) -> Error {
    if err:=set_map(&e.saved_outputs,o.id,o.settings); err!=nil { return err }
    if o.view!=nil { set_str(&o.failure,"") }
    if err:=sync_activity(e); err!=nil { return err }
    redraw(e); notify(e)
    return nil
}
