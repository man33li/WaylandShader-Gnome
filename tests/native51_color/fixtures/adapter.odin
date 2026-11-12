package main

import "base:runtime"
import glib "../glib"

// This fixture is a decision oracle, not a GPU, target ABI or Mutter implementation.
GNOME51 :: true
Color_Transform :: glib.Object
Color_Pipeline :: glib.Object
Color_Op :: glib.Object
boundary_context :: proc "contextless" () -> runtime.Context { return runtime.default_context() }
Mode :: enum { none, nil_transform, nil_pipeline, missing, null_texture, wrong_type, wrong_width, wrong_height, unknown_first, unknown_last, zero_curve, oversized_curve, zero_lut, oversized_lut, aggregate }
mode:Mode
reverse_only:bool
transform_calls,helper_calls,getter_calls:int
cpu_owners: [256]^Color_Transform
op_owners: [256]^Color_Pipeline
cpu_links: [256][3]glib.GList
cpu_modes: [256]Mode
cpu_sources,cpu_targets: [256]^Color_State
sizes: [256]uintptr
layers: [256][3]struct { index:i32, texture:^Texture }
layer_counts: [256]int
enumerating:^Pipeline
enumerated_layer:i32

adapter_reset :: proc() {
    mode=.none; reverse_only=false; transform_calls=0; helper_calls=0; getter_calls=0
    cpu_owners={}; op_owners={}; cpu_links={}; cpu_modes={}; cpu_sources={}; cpu_targets={}; sizes={}; layers={}; layer_counts={}; enumerating=nil
}
child :: proc(parent,p: ^glib.Object) {
    assert(parent.refs>0 && p.refs>0 && parent.child_count<len(parent.children))
    parent.children[parent.child_count]=p; parent.child_count+=1
}
clutter_color_transform_new :: proc(source,target:^Color_State,flags:u32) -> ^Color_Transform {
    assert(source.refs>0 && target.refs>0 && flags==0)
    transform_calls+=1
    selected:=mode if !reverse_only || transform_calls==2 else Mode.none
    if selected==.nil_transform { return nil }
    t:=glib.make(30); c:=glib.make(31)
    t.held=c; cpu_owners[c.id]=t; cpu_modes[c.id]=selected
    cpu_sources[c.id]=source; cpu_targets[c.id]=target
    // Three independent op IDs: gamma, curve, LUT. Indices include resource-free gamma.
    kinds:=[3]int{16,10,11}
    if selected==.unknown_first { kinds[0]=999 }
    if selected==.unknown_last { kinds[2]=999 }
    for kind,j in kinds {
        op:=glib.make(kind); child(c,op); op_owners[op.id]=c
        sizes[op.id]=4 if j==1 else 3
        if j==1 {
            if selected==.zero_curve { sizes[op.id]=0 }
            if selected==.oversized_curve { sizes[op.id]=0xffffffffffffffff }
            if selected==.aggregate { sizes[op.id]=4194304 }
        }
        if j==2 {
            if selected==.zero_lut { sizes[op.id]=0 }
            if selected==.oversized_lut { sizes[op.id]=0xffffffff }
        }
        cpu_links[c.id][j].data=op
        if j>0 { cpu_links[c.id][j-1].next=&cpu_links[c.id][j] }
    }
    return t
}
clutter_color_transform_get_pipeline :: proc(t:^Color_Transform) -> ^Color_Pipeline {
    assert(t.refs>0)
    if cpu_modes[t.held.id]==.nil_pipeline { return nil }
    return t.held
}
clutter_color_pipeline_get_ops :: proc(c:^Color_Pipeline) -> ^glib.GList {
    assert(c.refs>0 && cpu_owners[c.id].refs>0,"borrowed pipeline outlived its transform")
    return &cpu_links[c.id][0]
}
clutter_color_op_curve_1d_get_data :: proc(op:^Color_Op,size:^uintptr,r,g,b,a:^^f32) {
    assert(op.refs>0 && op_owners[op.id].refs>0 && cpu_owners[op_owners[op.id].id].refs>0)
    assert(op.kind==10 && r==nil && g==nil && b==nil && a==nil)
    size^=sizes[op.id]
}
clutter_color_op_3d_lut_get_data :: proc(op:^Color_Op,size:^u32,data:^^f32) {
    assert(op.refs>0 && op_owners[op.id].refs>0 && cpu_owners[op_owners[op.id].id].refs>0)
    assert(op.kind==11 && data==nil); size^=u32(sizes[op.id])
}
bind_fixture_texture :: proc(p:^Pipeline,index:i32,width,height:u32,kind:int=100) {
    assert(layer_counts[p.id]<3)
    tex:=glib.make(kind); sizes[tex.id]=uintptr(width)
    // Texture metadata is independent of op metadata and uses ctx only as an integer slot.
    tex.ctx=rawptr(uintptr(height))
    j:=layer_counts[p.id]; layers[p.id][j]={index,tex}; layer_counts[p.id]+=1
    child(p,cast(^glib.Object)glib.g_object_ref(tex)); glib.g_object_unref(tex)
}
clutter_color_pipeline_shader_add_transform :: proc(c:^Color_Pipeline,p:^Pipeline) {
    assert(c.refs>0 && cpu_owners[c.id].refs>0 && p.refs>0)
    helper_calls+=1
    transforms[p.id]={cpu_sources[c.id],cpu_targets[c.id],0}
    m:=cpu_modes[c.id]
    // Literal expected resources, deliberately not calling the production shape helper.
    bind_fixture_texture(p,12,3,9)
    bind_fixture_texture(p,0,17,19)
    if m!=.missing {
        if m==.null_texture {
            layers[p.id][layer_counts[p.id]]={11,nil}; layer_counts[p.id]+=1
        } else {
            bind_fixture_texture(p,11,5 if m==.wrong_width else 4,2 if m==.wrong_height else 1,101 if m==.wrong_type else 100)
        }
    }
}
cogl_pipeline_foreach_layer :: proc(p:^Pipeline,callback:proc "c"(p:^Pipeline,layer:i32,data:rawptr)->b32,data:rawptr) {
    assert(p.refs>0 && enumerating==nil)
    enumerating=p
    for i in 0..<layer_counts[p.id] {
        enumerated_layer=layers[p.id][i].index
        if !bool(callback(p,enumerated_layer,data)) { break }
    }
    enumerating=nil
}
cogl_pipeline_get_layer_texture :: proc(p:^Pipeline,index:i32) -> ^Texture {
    assert(enumerating==p && enumerated_layer==index,"getter manufactured or looked up an unenumerated layer")
    getter_calls+=1
    for i in 0..<layer_counts[p.id] { if layers[p.id][i].index==index { return layers[p.id][i].texture } }
    panic("missing-layer getter is forbidden even if a default could have matched")
}
cogl_texture_get_width :: proc(tex:^Texture) -> u32 { assert(tex.refs>0); return u32(sizes[tex.id]) }
cogl_texture_get_height :: proc(tex:^Texture) -> u32 { assert(tex.refs>0); return u32(uintptr(tex.ctx)) }
cogl_texture_2d_get_type :: proc() -> glib.GType { return 100 }
clutter_color_op_curve_1d_get_type :: proc() -> glib.GType { return 10 }
clutter_color_op_3d_lut_get_type :: proc() -> glib.GType { return 11 }
clutter_color_op_clamp_unit_get_type :: proc() -> glib.GType { return 12 }
clutter_color_op_srgb_piecewise_eotf_get_type :: proc() -> glib.GType { return 13 }
clutter_color_op_srgb_piecewise_inv_eotf_get_type :: proc() -> glib.GType { return 14 }
clutter_color_op_pq_eotf_get_type :: proc() -> glib.GType { return 15 }
clutter_color_op_gamma_power_get_type :: proc() -> glib.GType { return 16 }
clutter_color_op_pq_inv_eotf_get_type :: proc() -> glib.GType { return 17 }
clutter_color_op_unpremultiply_get_type :: proc() -> glib.GType { return 18 }
clutter_color_op_premultiply_get_type :: proc() -> glib.GType { return 19 }
clutter_color_op_matrix_4x4_get_type :: proc() -> glib.GType { return 20 }
clutter_color_op_ycbcr_matrix_get_type :: proc() -> glib.GType { return 21 }
clutter_color_op_multiply_get_type :: proc() -> glib.GType { return 22 }

adapter_failures_are_atomic :: proc() {
    bad:=[?]Mode{.nil_transform,.nil_pipeline,.missing,.null_texture,.wrong_type,.wrong_width,.wrong_height,.unknown_first,.unknown_last,.zero_curve,.oversized_curve,.zero_lut,.oversized_lut,.aggregate}
    for reverse in ([?]bool{false,true}) {
        for f in bad {
            i:=inputs(); r:=Resources{raw={fb=i.fb}}
            assert(configure_color(&r,i.target,i.srgb)==nil)
            other:=color(i.clutter); before:=r; refs:=glib.live_refs()
            transform_calls=0; mode=f; reverse_only=reverse
            assert(configure_color(&r,other,i.srgb)!=nil,"bad transform accepted")
            assert(r==before && glib.live_refs()==refs,"failed candidate published or leaked/dropped refs")
            mode=.none; reverse_only=false
            glib.g_object_unref(other); finish(i,&r)
        }
    }
}
adapter_sparse_resources_and_lifetime :: proc() {
    i:=inputs(); r:=Resources{raw={fb=i.fb}}
    assert(configure_color(&r,i.target,i.srgb)==nil)
    assert(helper_calls==2 && getter_calls==4 && transform_calls==2)
    // All borrowed CPU resources are dead; GPU texture refs are still owned by both pipelines.
    for n in 0..<glib.count { if glib.objects[n].kind==30 || glib.objects[n].kind==31 || glib.objects[n].kind==10 || glib.objects[n].kind==11 || glib.objects[n].kind==16 { assert(glib.objects[n].refs==0) } }
    for p in ([?]^Pipeline{r.to_srgb,r.to_target}) {
        for j in 0..<p.child_count { assert(p.children[j].refs>0) }
    }
    assert(configure_color(&r,i.target,i.srgb)==nil && transform_calls==2)
    finish(i,&r)
}
adapter_upload_boundaries :: proc() {
    i:=inputs(); t:=clutter_color_transform_new(i.target,i.srgb,0); c:=t.held
    curve:=cast(^Color_Op)cpu_links[c.id][1].data
    lut:=cast(^Color_Op)cpu_links[c.id][2].data
    // Independent literals, not copied acceptance conditions.
    for n in ([?]uintptr{0,1,4194305,0xffffffffffffffff}) { sizes[curve.id]=n; _,err:=color_resource_shape(curve); assert(err!=nil) }
    sizes[curve.id]=4194304; shape,err:=color_resource_shape(curve); assert(err==nil && shape.width==4194304 && shape.height==1 && shape.bytes==67108864)
    for n in ([?]uintptr{0,1,0xffffffff}) { sizes[lut.id]=n; _,err=color_resource_shape(lut); assert(err!=nil) }
    sizes[lut.id]=3; shape,err=color_resource_shape(lut); assert(err==nil && shape.width==3 && shape.height==9 && shape.bytes==432)
    glib.g_object_unref(t)
    r:Resources; finish(i,&r)
}
