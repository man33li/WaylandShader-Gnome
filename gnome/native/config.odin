package waylandshader

import "base:runtime"
import json "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import common "../common"
import glib "../glib"
import sr "../runtime"

key :: proc(w: ^common.Writer,name: string) { common.quote(w,name); common.put(w,":") }
settings_json :: proc(w: ^common.Writer,s: common.Output_Settings) {
    common.put(w,"{"); key(w,"colorEnabled"); common.boolean(w,s.color_enabled); common.put(w,","); key(w,"gamma"); common.number(w,s.gamma); common.put(w,","); key(w,"saturation"); common.number(w,s.saturation); common.put(w,","); key(w,"shaderEnabled"); common.boolean(w,s.shader_enabled); common.put(w,"}")
}
write_recent :: proc(w: ^common.Writer,recent: []string) { common.put(w,"["); for path,i in recent { if i>0 { common.put(w,",") }; common.quote(w,path) }; common.put(w,"]") }
status_json :: proc(e: ^Engine) -> (string,Error) {
    w:common.Writer
    common.put(&w,"{"); key(&w,"active"); common.boolean(&w,active(e)); common.put(&w,","); key(&w,"enabled"); common.boolean(&w,e.enabled); common.put(&w,","); key(&w,"error"); common.quote(&w,e.error); common.put(&w,","); key(&w,"loading"); common.boolean(&w,e.loading)
    common.put(&w,","); key(&w,"outputs"); common.put(&w,"[")
    for o,i in e.outputs {
        if i>0 { common.put(&w,",") }; common.put(&w,"{")
        if len(o.failure)>0 { key(&w,"bypass"); common.quote(&w,o.failure); common.put(&w,",") }
        key(&w,"colorActive"); common.boolean(&w,color(e,o)); common.put(&w,","); key(&w,"colorEnabled"); common.boolean(&w,o.settings.color_enabled); common.put(&w,","); key(&w,"gamma"); common.number(&w,o.settings.gamma); common.put(&w,","); key(&w,"id"); common.quote(&w,o.id); common.put(&w,","); key(&w,"name"); common.quote(&w,o.name); common.put(&w,","); key(&w,"saturation"); common.number(&w,o.settings.saturation); common.put(&w,","); key(&w,"shaderActive"); common.boolean(&w,shader(e,o)); common.put(&w,","); key(&w,"shaderEnabled"); common.boolean(&w,o.settings.shader_enabled); common.put(&w,"}")
    }
    common.put(&w,"],"); key(&w,"parameters"); common.put(&w,"[")
    parameters:=e.last_parameters[:]
    if e.runtime!=nil { parameters=e.runtime.parameters[:] }
    for p,i in parameters {
        if i>0 { common.put(&w,",") }; common.put(&w,"{"); key(&w,"default"); common.number(&w,p.default_value); common.put(&w,","); key(&w,"description"); common.quote(&w,p.description); common.put(&w,","); key(&w,"maximum"); common.number(&w,p.maximum); common.put(&w,","); key(&w,"minimum"); common.number(&w,p.minimum); common.put(&w,","); key(&w,"name"); common.quote(&w,p.name); common.put(&w,","); key(&w,"step"); common.number(&w,p.step); common.put(&w,","); key(&w,"value"); common.number(&w,p.value); common.put(&w,"}")
    }
    common.put(&w,"],"); key(&w,"preset"); common.quote(&w,e.preset); common.put(&w,","); key(&w,"recentPresets"); write_recent(&w,e.recent[:]); common.put(&w,","); key(&w,"requestedPreset"); common.quote(&w,e.requested); common.put(&w,"}")
    if w.error!=nil { err:=w.error; common.destroy(&w); return "",err }
    return common.finish(&w),nil
}
sorted_keys :: proc(m: map[string]$T) -> ([]string,Error) {
    keys,ae:=make([]string,len(m),context.temp_allocator)
    if ae!=nil { return nil,"Out of memory" }
    i:=0; for k in m { keys[i]=k; i+=1 }; slice.sort_by(keys,common.utf16_less)
    return keys,nil
}
export_json :: proc(e: ^Engine) -> (string,Error) {
    w:common.Writer
    success:=false; defer if !success { common.destroy(&w) }
    common.put(&w,"{"); key(&w,"enabled"); common.boolean(&w,e.enabled); common.put(&w,","); key(&w,"outputs"); common.put(&w,"{")
    output_keys,err:=sorted_keys(e.saved_outputs)
    if err!=nil { return "",err }
    for id,i in output_keys { if i>0 { common.put(&w,",") }; key(&w,id); settings_json(&w,e.saved_outputs[id]) }
    common.put(&w,"},"); key(&w,"parameters"); common.put(&w,"{")
    preset_keys,pe:=sorted_keys(e.overrides)
    if pe!=nil { return "",pe }
    for preset,i in preset_keys {
        if i>0 { common.put(&w,",") }; key(&w,preset); common.put(&w,"{")
        parameters:=e.overrides[preset]; names,ne:=sorted_keys(parameters)
        if ne!=nil { return "",ne }
        for name,j in names { if j>0 { common.put(&w,",") }; key(&w,name); common.number(&w,parameters[name]) }
        common.put(&w,"}")
    }
    common.put(&w,"},"); key(&w,"preset"); common.quote(&w,e.preset); common.put(&w,","); key(&w,"recent_presets"); write_recent(&w,e.recent[:]); common.put(&w,","); key(&w,"version"); common.put(&w,"1}")
    if w.error!=nil { return "",w.error }
    success=true
    return common.finish(&w),nil
}
parse_document :: proc(source: string) -> (json.Value,Error) { return common.parse_json(source,context.temp_allocator) }
read_boolean :: proc(o: json.Object,name: string,fallback: bool) -> (bool,Error) {
    value,exists:=o[name]; if !exists { return fallback,nil }
    result,ok:=value.(json.Boolean); if !ok { return false,fmt.tprintf("%s must be boolean",name) }
    return bool(result),nil
}
read_number :: proc(o: json.Object,name: string,fallback,minimum,maximum: f64) -> (f64,Error) {
    value,exists:=o[name]; if !exists { return fallback,nil }
    result,ok:=value.(json.Float)
    if !ok || math.is_nan(result) || math.is_inf(result) || f64(result)<minimum || f64(result)>maximum { return 0,fmt.tprintf("%s is outside its allowed range",name) }
    return f64(result),nil
}
read_settings :: proc(o: json.Object) -> (common.Output_Settings,Error) {
    s:=common.DEFAULT_OUTPUT_SETTINGS; err:Error
    s.shader_enabled,err=read_boolean(o,"shaderEnabled",true); if err!=nil { return s,err }
    s.color_enabled,err=read_boolean(o,"colorEnabled",false); if err!=nil { return s,err }
    s.gamma,err=read_number(o,"gamma",1,common.MIN_GAMMA,common.MAX_GAMMA); if err!=nil { return s,err }
    s.saturation,err=read_number(o,"saturation",1,common.MIN_SATURATION,common.MAX_SATURATION)
    return s,err
}
free_recent :: proc(recent: ^[dynamic]string) { for path in recent^ { delete(path) }; delete(recent^); recent^=nil }
recent_append :: proc(recent: ^[dynamic]string,path: string) -> Error {
    if len(recent^)>=10 { return nil }
    for old in recent^ { if old==path { return nil } }
    copied,ae:=strings.clone(path)
    if ae!=nil { return "Out of memory" }
    if _,err:=append(recent,copied); err!=nil { delete(copied); return "Out of memory" }
    return nil
}
recent_prepend :: proc(e: ^Engine,path: string) -> Error {
    next:[dynamic]string
    success:=false; defer if !success { free_recent(&next) }
    if err:=recent_append(&next,path); err!=nil { return err }
    for old in e.recent { if err:=recent_append(&next,old); err!=nil { return err } }
    free_recent(&e.recent); e.recent=next; success=true
    return nil
}
import_settings :: proc(e: ^Engine,source: string) -> Error {
    if e.loading || e.job!=nil { return "Cannot import settings while a preset is compiling" }
    if e.renderer_failed { return e.error if len(e.error)>0 else "The GNOME renderer is unavailable" }
    document,parse_error:=parse_document(source)
    if parse_error!=nil { return parse_error }
    o,ok:=document.(json.Object)
    if !ok { return "Configuration must be a JSON object" }
    version,version_ok:=o["version"].(json.Float)
    if len(o)>0 && (!version_ok || version!=1) { return "Unsupported settings version" }
    enabled,enabled_error:=read_boolean(o,"enabled",true)
    if enabled_error!=nil { return enabled_error }
    preset:string
    if v,exists:=o["preset"]; exists { p,is_string:=v.(json.String); if !is_string { return "Preset must be a string" }; preset=string(p) }
    saved:map[string]common.Output_Settings
    overrides:map[string]map[string]f64
    recent:[dynamic]string
    success:=false
    defer if !success { for k in saved { delete(k) }; delete(saved); for k,values in overrides { for name in values { delete(name) }; delete(values); delete(k) }; delete(overrides); free_recent(&recent) }
    if v,exists:=o["outputs"]; exists {
        outputs,outputs_object:=v.(json.Object); if !outputs_object { return "Output settings must be an object" }
        ids,se:=sorted_keys(cast(map[string]json.Value)outputs); if se!=nil { return se }
        for id in ids {
            values,is_object:=outputs[id].(json.Object)
            if len(id)==0 || !is_object { return "Invalid saved output settings" }
            settings,read_error:=read_settings(values)
            if read_error!=nil { return read_error }
            if err:=set_map(&saved,id,settings); err!=nil { return err }
        }
    }
    if v,exists:=o["parameters"]; exists {
        presets,presets_object:=v.(json.Object); if !presets_object { return "Parameter settings must be an object" }
        paths,se:=sorted_keys(cast(map[string]json.Value)presets); if se!=nil { return se }
        for path in paths {
            values,is_object:=presets[path].(json.Object); if !is_object { return "Invalid saved preset parameters" }
            parameters:map[string]f64
            inserted:=false
            defer if !inserted { for name in parameters { delete(name) }; delete(parameters) }
            names,ne:=sorted_keys(cast(map[string]json.Value)values); if ne!=nil { return ne }
            for name in names {
                value,is_number:=values[name].(json.Float)
                if len(name)==0 || !is_number || math.is_nan(value) || math.is_inf(value) { return "Saved parameters must have finite numeric values" }
                if err:=set_map(&parameters,name,f64(value)); err!=nil { return err }
            }
            if err:=set_map(&overrides,path,parameters); err!=nil { return err }; inserted=true
        }
    }
    if len(preset)>0 && preset[0]!='/' { return "Saved preset must be an absolute filename" }
    if entries,is_array:=o["recent_presets"].(json.Array); is_array {
        for entry in entries {
            path,is_string:=entry.(json.String)
            if is_string && len(path)>=7 && path[0]=='/' && strings.equal_fold(string(path)[len(path)-7:],".slangp") { if err:=recent_append(&recent,string(path)); err!=nil { return err } }
        }
    }
    for k in e.saved_outputs { delete(k) }; delete(e.saved_outputs)
    for k,values in e.overrides { for name in values { delete(name) }; delete(values); delete(k) }; delete(e.overrides)
    free_recent(&e.recent); e.saved_outputs=saved; e.overrides=overrides; e.recent=recent; e.enabled=enabled; success=true
    for output in e.outputs { settings,exists:=e.saved_outputs[output.id]; output.settings=settings if exists else common.DEFAULT_OUTPUT_SETTINGS }
    if len(preset)>0 {
        p,ae:=strings.clone_to_cstring(preset,context.temp_allocator); if ae!=nil { return "Out of memory" }
        canonical:cstring
        if !strings.contains_rune(preset,0) { canonical=sr.canonical_path(p,nil) }
        restored:=preset
        if canonical!=nil { restored=string(canonical) }
        defer if canonical!=nil { sr.c_free(rawptr(canonical)) }
        if err:=request(e,restored); err!=nil { return err }
        if e.runtime==nil && len(e.preset)==0 { if err:=set_str(&e.preset,restored); err!=nil { return err } }
    } else { set_str(&e.preset,""); set_str(&e.requested,""); free_parameters(&e.last_parameters); if err:=reset(e,false); err!=nil { return err } }
    if err:=sync_activity(e); err!=nil { return err }; redraw(e); notify(e)
    return nil
}
coordinate :: proc(o: json.Object,name: string,minimum: f64) -> (i32,Error) {
    if _,exists:=o[name]; !exists { return 0,"Output is missing geometry" }
    value,err:=read_number(o,name,0,minimum,2147483647)
    if err!=nil { return 0,err }
    if math.floor(value)!=value { return 0,"Output geometry must use integer logical coordinates" }
    return i32(value),nil
}
set_outputs :: proc(e: ^Engine,source: string) -> Error {
    document,document_error:=parse_document(source)
    if document_error!=nil { return document_error }
    array,array_ok:=document.(json.Array); if !array_ok { return "Outputs must be a JSON array" }
    next:[dynamic]^Output
    views:[dynamic]Output_View
    success:=false
    defer if !success { for o in next { destroy_output(o) }; delete(next); delete(views) }
    for value in array {
        o,ok:=value.(json.Object); if !ok { return "Each output must be an object" }
        id,id_ok:=o["id"].(json.String); name,name_ok:=o["name"].(json.String)
        if !id_ok || !name_ok { return "Output IDs and names must be strings" }
        output,allocation_error:=new(Output); if allocation_error!=nil { return "Out of memory" }
        output.engine=e; output.key=e.next_key; e.next_key+=1; output.scale=1; reset_clock(output)
        owned:=false; defer if !owned { destroy_output(output) }
        if err:=set_str(&output.id,string(id)); err!=nil { return err }; if err:=set_str(&output.name,string(name)); err!=nil { return err }
        duplicate:=false; for previous in next { if previous.id==string(id) { duplicate=true; break } }
        if len(id)==0 || duplicate { return "Output IDs must be nonempty and unique" }
        geometry_error:Error
        output.layout.x,geometry_error=coordinate(o,"x",-2147483648); if geometry_error!=nil { return geometry_error }
        output.layout.y,geometry_error=coordinate(o,"y",-2147483648); if geometry_error!=nil { return geometry_error }
        output.layout.width,geometry_error=coordinate(o,"width",1); if geometry_error!=nil { return geometry_error }
        output.layout.height,geometry_error=coordinate(o,"height",1); if geometry_error!=nil { return geometry_error }
        if _,exists:=o["scale"]; !exists { return "Output is missing its scale" }
        output.scale,geometry_error=read_number(o,"scale",1,.01,64); if geometry_error!=nil { return geometry_error }
        settings,exists:=e.saved_outputs[output.id]; output.settings=settings if exists else common.DEFAULT_OUTPUT_SETTINGS
        if _,ae:=append(&next,output); ae!=nil { return "Out of memory" }; owned=true
        if _,ae:=append(&views,Output_View{nil,-1}); ae!=nil { return "Out of memory" }
    }
    same:=len(next)==len(e.outputs)
    for o,i in next { if !same { break }; old:=e.outputs[i]; same=o.id==old.id && o.name==old.name && o.scale==old.scale && o.layout==old.layout }
    if same && !e.mapping_dirty { return nil }
    if err:=reset(e,true); err!=nil { return err }
    for o in e.outputs { destroy_output(o) }; delete(e.outputs); delete(e.views)
    e.outputs=next; e.views=views; success=true; e.mapping_dirty=true
    if err:=map_outputs(e); err!=nil { return err }; redraw(e); notify(e)
    return nil
}
load_preset :: proc(e: ^Engine,path: string) -> Error {
    cpath,ae:=strings.clone_to_cstring(path,context.temp_allocator)
    if ae!=nil { return "Out of memory" }
    if len(path)==0 || path[0]!='/' || !glib.g_file_test(cpath,1) || sr.file_access(cpath,4)!=0 { return "Preset must be an absolute readable file" }
    canonical:=sr.canonical_path(cpath,nil)
    if canonical==nil { return "Unable to resolve preset filename" }
    defer sr.c_free(rawptr(canonical))
    return request(e,string(canonical))
}
set_enabled :: proc(e: ^Engine,value: bool) -> Error { if e.enabled==value { return nil }; e.enabled=value; if err:=reset(e,value); err!=nil { return err }; return sync_activity(e) }
set_parameter :: proc(e: ^Engine,name: string,value: f64) -> Error {
    if e.loading || len(e.preset)==0 { return "No ready preset, or compilation is in progress" }
    if e.runtime!=nil {
        if err:=sr.set_parameter(e.runtime,name,value); err!=nil { return err }
        if err:=clone_parameters(&e.last_parameters,e.runtime.parameters[:]); err!=nil { return err }
    } else {
        found:=false
        for &parameter in e.last_parameters { if parameter.name==name { found=true; if err:=sr.validate_value(&parameter,value); err!=nil { return err }; parameter.value=f64(f32(value)); break } }
        if !found { return fmt.tprintf("Unknown shader parameter '%s'",name) }
    }
    parameters,exists:=e.overrides[e.preset]
    if !exists { if err:=set_map(&e.overrides,e.preset,parameters); err!=nil { return err } }
    if err:=set_map(&parameters,name,value); err!=nil { return err }
    e.overrides[e.preset]=parameters
    redraw(e); notify(e)
    return nil
}
output_mutate :: proc(e: ^Engine,id: string,kind: u32,value: f64) -> Error {
    if kind==2 && (math.is_nan(value)||math.is_inf(value)||value<common.MIN_GAMMA||value>common.MAX_GAMMA) { return "Gamma must be finite and between 0.1 and 5" }
    if kind==3 && (math.is_nan(value)||math.is_inf(value)||value<common.MIN_SATURATION||value>common.MAX_SATURATION) { return "Saturation must be finite and between 0 and 2" }
    o,err:=find_output(e,id); if err!=nil { return err }
    switch kind {
    case 0: requested:=value!=0; if o.settings.shader_enabled==requested { return nil }; o.settings.shader_enabled=requested; reset_clock(o)
    case 1: requested:=value!=0; if o.settings.color_enabled==requested { return nil }; o.settings.color_enabled=requested
    case 2: if o.settings.gamma==value { return nil }; o.settings.gamma=value
    case 3: if o.settings.saturation==value { return nil }; o.settings.saturation=value
    }
    return changed(e,o)
}

@(export)
wayland_shader_effect_export_settings :: proc "c" (self: ^Effect) -> cstring {
    context=boundary_context(); runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    if self==nil || !glib.g_type_check_instance_is_a(self,wayland_shader_effect_get_type()) || self.engine==nil { return nil }
    value,err:=export_json(self.engine); if err!=nil { return nil }; defer delete(value)
    return glib.g_strndup(raw_data(value),len(value))
}
@(export)
wayland_shader_effect_import_settings :: proc "c" (self: ^Effect,value: cstring,destination: ^^glib.Error) -> b32 {
    context=boundary_context(); runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    e,err:=get_engine(self); if err!=nil { return mutate(err,destination) }
    if e.loading || e.job!=nil { return mutate("Cannot import settings while a preset is compiling",destination) }
    if e.renderer_failed { return mutate(e.error if len(e.error)>0 else "The GNOME renderer is unavailable",destination) }
    source,te:=text(value); if te!=nil { return mutate(te,destination) }; return mutate(import_settings(e,source),destination)
}
@(export)
wayland_shader_effect_set_outputs :: proc "c" (self: ^Effect,value: cstring,destination: ^^glib.Error) -> b32 {
    context=boundary_context(); runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    e,err:=get_engine(self); if err!=nil { return mutate(err,destination) }; source,te:=text(value); if te!=nil { return mutate(te,destination) }; return mutate(set_outputs(e,source),destination)
}
@(export)
wayland_shader_effect_load_preset :: proc "c" (self: ^Effect,value: cstring,destination: ^^glib.Error) -> b32 {
    context=boundary_context(); runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    e,err:=get_engine(self); if err!=nil { return mutate(err,destination) }; path,te:=text(value); if te!=nil { return mutate(te,destination) }; return mutate(load_preset(e,path),destination)
}
@(export)
wayland_shader_effect_set_enabled :: proc "c" (self: ^Effect,value: b32,destination: ^^glib.Error) -> b32 {
    context=boundary_context(); runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    e,err:=get_engine(self); if err!=nil { return mutate(err,destination) }; return mutate(set_enabled(e,bool(value)),destination)
}
@(export)
wayland_shader_effect_set_parameter :: proc "c" (self: ^Effect,value: cstring,number: f64,destination: ^^glib.Error) -> b32 {
    context=boundary_context(); runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    e,err:=get_engine(self); if err!=nil { return mutate(err,destination) }
    if e.loading || len(e.preset)==0 { return mutate("No ready preset, or compilation is in progress",destination) }
    name,te:=text(value); if te!=nil { return mutate(te,destination) }; return mutate(set_parameter(e,name,number),destination)
}
output_entry :: proc(self: ^Effect,id: cstring,kind: u32,value: f64,destination: ^^glib.Error) -> b32 {
    e,err:=get_engine(self); if err!=nil { return mutate(err,destination) }
    if kind==2 && (math.is_nan(value)||math.is_inf(value)||value<.1||value>5) { return mutate("Gamma must be finite and between 0.1 and 5",destination) }
    if kind==3 && (math.is_nan(value)||math.is_inf(value)||value<0||value>2) { return mutate("Saturation must be finite and between 0 and 2",destination) }
    name,te:=text(id); if te!=nil { return mutate(te,destination) }; return mutate(output_mutate(e,name,kind,value),destination)
}
@(export)
wayland_shader_effect_set_output_shader_enabled :: proc "c" (self: ^Effect,id: cstring,value: b32,destination: ^^glib.Error) -> b32 { context=boundary_context(); runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(); return output_entry(self,id,0,1 if value else 0,destination) }
@(export)
wayland_shader_effect_set_output_color_enabled :: proc "c" (self: ^Effect,id: cstring,value: b32,destination: ^^glib.Error) -> b32 { context=boundary_context(); runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(); return output_entry(self,id,1,1 if value else 0,destination) }
@(export)
wayland_shader_effect_set_output_gamma :: proc "c" (self: ^Effect,id: cstring,value: f64,destination: ^^glib.Error) -> b32 { context=boundary_context(); runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(); return output_entry(self,id,2,value,destination) }
@(export)
wayland_shader_effect_set_output_saturation :: proc "c" (self: ^Effect,id: cstring,value: f64,destination: ^^glib.Error) -> b32 { context=boundary_context(); runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(); return output_entry(self,id,3,value,destination) }
@(export)
wayland_shader_effect_reset_history :: proc "c" (self: ^Effect) { context=boundary_context(); runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(); e,err:=get_engine(self); if err==nil { err=reset(e,true) }; if err!=nil && self!=nil && glib.g_type_check_instance_is_a(self,wayland_shader_effect_get_type()) && self.engine!=nil { fail(self.engine,error_message(err)) } }
