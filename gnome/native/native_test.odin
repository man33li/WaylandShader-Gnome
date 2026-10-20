package waylandshader

import "base:runtime"
import "core:mem"
import "core:testing"
import "core:thread"
import glib "../glib"
import sr "../runtime"

@(test)
frame_clock_cases :: proc(t: ^testing.T) {
    c:=Frame_Clock{first_frame=-1,clear_history=true}
    render,fps,elapsed,number:=frame_timing(&c,100,1000000,60)
    testing.expect(t,render); testing.expect_value(t,fps,f32(60)); testing.expect_value(t,elapsed,u32(0)); testing.expect_value(t,number,u64(0)); testing.expect(t,c.clear_history)
    c.previous_time=1000000
    render,fps,elapsed,number=frame_timing(&c,103,1017000,60)
    testing.expect(t,render); testing.expect_value(t,elapsed,u32(17)); testing.expect_value(t,number,u64(3))
    _,_,elapsed,number=frame_timing(&c,99,999000,60)
    testing.expect_value(t,elapsed,u32(0)); testing.expect_value(t,number,u64(0))
    _,_,elapsed,_=frame_timing(&c,104,1000000+i64(0xffffffff)*1000+9999,60)
    testing.expect_value(t,elapsed,u32(0xffffffff))
    c={first_frame=-1,clear_history=true}
    render,_,_,_=frame_timing(&c,10,1000000,0)
    testing.expect(t,!render); testing.expect_value(t,c.previous_time,i64(1000000)); testing.expect_value(t,c.first_frame,i64(-1))
    render,fps,elapsed,number=frame_timing(&c,11,1020000,0)
    testing.expect(t,render); testing.expect_value(t,fps,f32(50)); testing.expect_value(t,elapsed,u32(20)); testing.expect_value(t,number,u64(0))
}
@(test)
selection_and_zero_allocations :: proc(t: ^testing.T) {
    first:=cast(^Stage_View)uintptr(1); second:=cast(^Stage_View)uintptr(2)
    views:=[2]Output_View{{first,7},{second,9}}
    testing.expect_value(t,select_output(views[:],second,9),1)
    testing.expect_value(t,select_output(views[:],second,8),-1)
    testing.expect_value(t,select_output(views[:],nil,7),-1)
    c:=Frame_Clock{first_frame=-1,clear_history=true}
    frame_timing(&c,0,1000000,60); select_output(views[:],first,7)
    heap,temp:mem.Tracking_Allocator
    mem.tracking_allocator_init(&heap,context.allocator); mem.tracking_allocator_init(&temp,context.temp_allocator)
    old_heap,old_temp:=context.allocator,context.temp_allocator
    context.allocator=mem.tracking_allocator(&heap); context.temp_allocator=mem.tracking_allocator(&temp)
    before_heap,before_temp:=heap.total_allocation_count,temp.total_allocation_count
    total:=0
    for i in 0..<100 { frame_timing(&c,i64(i),1000000+i64(i)*17000,60); total+=select_output(views[:],second,9) }
    heap_delta,temp_delta:=heap.total_allocation_count-before_heap,temp.total_allocation_count-before_temp
    context.allocator=old_heap; context.temp_allocator=old_temp
    mem.tracking_allocator_destroy(&heap); mem.tracking_allocator_destroy(&temp)
    testing.expect_value(t,total,100); testing.expect_value(t,heap_delta,i64(0)); testing.expect_value(t,temp_delta,i64(0))
}
Thread_Check :: struct { engine: ^Engine, error: Error }
wrong_thread :: proc(data: ^Thread_Check) { data.error=engine_check(data.engine) }
@(test)
owner_and_stopped :: proc(t: ^testing.T) {
    e:=Engine{owner=glib.g_thread_self()}
    testing.expect(t,engine_check(&e)==nil)
    e.stopped=true
    testing.expect_value(t,error_message(engine_check(&e)),"The native effect has shut down")
    data:=Thread_Check{engine=&e}
    worker:=thread.create_and_start_with_poly_data(&data,wrong_thread)
    testing.expect(t,worker!=nil)
    if worker!=nil { thread.join(worker); thread.destroy(worker) }
    testing.expect_value(t,error_message(data.error),"Native effect methods require the compositor main thread")
}
@(test)
snippet_and_error_formatters :: proc(t: ^testing.T) {
    testing.expect_value(t,SNIPPET_DECL,string(#load("../tests/golden/snippet-decl.glsl")))
    testing.expect_value(t,SNIPPET_BODY,string(#load("../tests/golden/snippet-body.glsl")))
    testing.expect_value(t,sr.egl_error_code("eglCreateContext",0x3009),"eglCreateContext failed (EGL error 0x3009)")
    testing.expect_value(t,sr.egl_error_code("probe",1),"probe failed (EGL error 0x0001)")
    testing.expect_value(t,gl_error("Stage presentation",0x502),"Stage presentation failed (GL 0x502)")
    testing.expect_value(t,sr.libra_fallback(7),"librashader failed (error 7)")
    p:=sr.Parameter{name="GAIN",minimum=.1,maximum=2}
    testing.expect(t,sr.validate_value(&p,.5)==nil)
    testing.expect_value(t,error_message(sr.validate_value(&p,3)),"Parameter 'GAIN' must be finite and between 0.1 and 2")
}
@(test)
configuration_validation :: proc(t: ^testing.T) {
    e:=Engine{owner=glib.g_thread_self(),mapping_dirty=true,next_key=1,enabled=true,main_ctx=glib.g_main_context_ref_thread_default()}
    defer { engine_shutdown(&e); delete(e.outputs); delete(e.views); free_recent(&e.recent); for k in e.saved_outputs { delete(k) }; delete(e.saved_outputs); for k,v in e.overrides { for name in v { delete(name) }; delete(v); delete(k) }; delete(e.overrides); delete(e.preset); delete(e.requested); delete(e.error); delete(e.pending); delete(e.last_status); free_parameters(&e.last_parameters); glib.g_main_context_unref(e.main_ctx) }
    testing.expect_value(t,error_message(import_settings(&e,"[]")),"Configuration must be a JSON object")
    testing.expect_value(t,error_message(import_settings(&e,`{"version":2}`)),"Unsupported settings version")
    testing.expect_value(t,error_message(set_outputs(&e,`[{"id":"A","name":"A","x":0,"y":0,"width":1,"height":1}]`)),"Output is missing its scale")
    testing.expect_value(t,error_message(set_outputs(&e,`[{"id":"A","name":"A","x":0.5,"y":0,"width":1,"height":1,"scale":1}]`)),"Output geometry must use integer logical coordinates")
    testing.expect(t,import_settings(&e,`{"version":1,"enabled":false,"recent_presets":["/a.slangp","relative.slangp",7,"/a.slangp","/B.SLANGP"]}`)==nil)
    testing.expect_value(t,len(e.recent),2)
    testing.expect_value(t,e.recent[1],"/B.SLANGP")
}

expect_load_snapshot :: proc(t: ^testing.T,e: ^Engine,has_gain: bool) {
    job,err:=new_load_job(e)
    testing.expect(t,err==nil)
    if job==nil { return }
    defer job_destroy(job)
    testing.expect_value(t,job.path,"/presets/fresh.slangp")
    testing.expect_value(t,job.generation,u64(42))
    testing.expect_value(t,len(job.keys),2)
    testing.expect_value(t,job.keys[0],uintptr(11))
    testing.expect_value(t,job.keys[1],uintptr(22))
    gain,present:=job.overrides["GAIN"]
    testing.expect_value(t,present,has_gain)
    if has_gain {
        testing.expect_value(t,gain,f64(.5))
        original:=e.overrides[e.pending]
        original["GAIN"]=.75
        testing.expect_value(t,job.overrides["GAIN"],f64(.5))
    }
}
@(test)
load_job_optional_overrides :: proc(t: ^testing.T) {
    first,second:=Output{key=11},Output{key=22}
    e:=Engine{pending="/presets/fresh.slangp",generation=42}
    _,allocation_error:=append(&e.outputs,&first,&second)
    testing.expect(t,allocation_error==nil)
    defer delete(e.outputs)
    defer {
        for path,values in e.overrides { for name in values { delete(name) }; delete(values); delete(path) }
        delete(e.overrides)
    }
    expect_load_snapshot(t,&e,false)
    empty:map[string]f64
    testing.expect(t,set_map(&e.overrides,"/presets/other.slangp",empty)==nil)
    expect_load_snapshot(t,&e,false)
    testing.expect(t,set_map(&e.overrides,e.pending,empty)==nil)
    expect_load_snapshot(t,&e,false)
    values:map[string]f64
    testing.expect(t,set_map(&values,"GAIN",f64(.5))==nil)
    e.overrides[e.pending]=values
    expect_load_snapshot(t,&e,true)
}

guarded_load_failure :: proc() -> string {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    _,failure:=sr.load(nil,nil,"",nil,nil)
    return failure
}
@(test)
runtime_load_error_ownership :: proc(t: ^testing.T) {
    failure:=guarded_load_failure()
    defer delete(failure)
    testing.expect_value(t,failure,"No desktop OpenGL EGL compositor context is available")
}
