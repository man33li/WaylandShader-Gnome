package waylandshader

import glib "../glib"

install_color_transform :: proc(source,target: ^Color_State,pipeline: ^Pipeline) -> Error {
    when GNOME51 { return install_color_transform_51(source,target,pipeline) }
    else { clutter_color_state_add_pipeline_transform(source,target,pipeline,0); return nil }
}
update_color_transform :: proc(source,target: ^Color_State,pipeline: ^Pipeline) {
    // 51's immutable transform writes its uniforms during installation; no legacy update API exists.
    when !GNOME51 { clutter_color_state_update_uniforms(source,target,pipeline) }
}

when GNOME51 {
    // Bounds upload scratch per transform, not total compositor CPU/GPU memory.
    COLOR_UPLOAD_LIMIT :: u64(64*1024*1024)
    COLOR_LAYER_OFFSET :: i64(10)
    Color_Resource :: struct { width,height: u32, bytes: u64 }
    Color_Layer_Search :: struct { wanted: i32, found: bool, texture: ^Texture }

    color_resource_shape :: proc(op: ^Color_Op) -> (Color_Resource,Error) {
        if op==nil { return {},"Invalid color operation" }
        if glib.g_type_check_instance_is_a(op,clutter_color_op_curve_1d_get_type()) {
            size:uintptr
            clutter_color_op_curve_1d_get_data(op,&size,nil,nil,nil,nil)
            if size<2 || u64(size)>COLOR_UPLOAD_LIMIT/16 { return {},"Unsupported color curve size" }
            return {u32(size),1,u64(size)*16},nil
        }
        if glib.g_type_check_instance_is_a(op,clutter_color_op_3d_lut_get_type()) {
            size:u32
            clutter_color_op_3d_lut_get_data(op,&size,nil)
            n:=u64(size)
            // Division precedes multiplication, including hostile uint32 sizes.
            if n<2 || n>COLOR_UPLOAD_LIMIT/16/n/n { return {},"Unsupported color LUT size" }
            return {size,u32(n*n),n*n*n*16},nil
        }
        // Match only the 51 shader helper's known resource-free operations. Unknown means error.
        if glib.g_type_check_instance_is_a(op,clutter_color_op_clamp_unit_get_type()) ||
           glib.g_type_check_instance_is_a(op,clutter_color_op_srgb_piecewise_eotf_get_type()) ||
           glib.g_type_check_instance_is_a(op,clutter_color_op_srgb_piecewise_inv_eotf_get_type()) ||
           glib.g_type_check_instance_is_a(op,clutter_color_op_pq_eotf_get_type()) ||
           glib.g_type_check_instance_is_a(op,clutter_color_op_pq_inv_eotf_get_type()) ||
           glib.g_type_check_instance_is_a(op,clutter_color_op_unpremultiply_get_type()) ||
           glib.g_type_check_instance_is_a(op,clutter_color_op_premultiply_get_type()) ||
           glib.g_type_check_instance_is_a(op,clutter_color_op_gamma_power_get_type()) ||
           glib.g_type_check_instance_is_a(op,clutter_color_op_matrix_4x4_get_type()) ||
           glib.g_type_check_instance_is_a(op,clutter_color_op_ycbcr_matrix_get_type()) ||
           glib.g_type_check_instance_is_a(op,clutter_color_op_multiply_get_type()) { return {},nil }
        return {},"Unsupported color operation"
    }
    find_color_layer :: proc "c" (pipeline: ^Pipeline,layer: i32,data: rawptr) -> b32 {
        context=boundary_context()
        search:=cast(^Color_Layer_Search)data
        if layer!=search.wanted { return true }
        search.found=true
        // This getter is legal only after enumeration proved that the layer already exists.
        search.texture=cogl_pipeline_get_layer_texture(pipeline,layer)
        return false
    }
    install_color_transform_51 :: proc(source,target: ^Color_State,pipeline: ^Pipeline) -> Error {
        transform:=clutter_color_transform_new(source,target,0)
        if transform==nil { return "Unable to create the color transform" }
        defer glib.g_object_unref(transform)
        color:=clutter_color_transform_get_pipeline(transform)
        if color==nil { return "Unable to obtain the color pipeline" }
        ops:=clutter_color_pipeline_get_ops(color) // borrowed const list; never modified or freed here
        bytes:u64=0
        index:=COLOR_LAYER_OFFSET
        for node:=ops; node!=nil; node=node.next {
            if index>0x7fffffff { return "Too many color operations" }
            resource,err:=color_resource_shape(cast(^Color_Op)node.data)
            if err!=nil { return err }
            if resource.bytes>COLOR_UPLOAD_LIMIT-bytes { return "Color transform upload capacity exceeded" }
            bytes+=resource.bytes
            index+=1
        }
        // The helper returns void even when a texture constructor failed. It is NOT our success oracle.
        clutter_color_pipeline_shader_add_transform(color,pipeline)
        index=COLOR_LAYER_OFFSET
        for node:=ops; node!=nil; node=node.next {
            resource,err:=color_resource_shape(cast(^Color_Op)node.data)
            if err!=nil { return err }
            if resource.width!=0 {
                search:=Color_Layer_Search{wanted=i32(index)}
                cogl_pipeline_foreach_layer(pipeline,find_color_layer,&search)
                if !search.found || search.texture==nil { return "Color transform is missing a required texture" }
                if !glib.g_type_check_instance_is_a(search.texture,cogl_texture_2d_get_type()) { return "Color transform texture is not 2D" }
                // LUT is deliberately flattened size x size², not a 3D texture; curve is size x 1.
                if cogl_texture_get_width(search.texture)!=resource.width || cogl_texture_get_height(search.texture)!=resource.height { return "Color transform texture dimensions do not match" }
            }
            index+=1
        }
        // Texture references belong to the Cogl pipeline; transform/ops remain alive through validation.
        return nil
    }
}
