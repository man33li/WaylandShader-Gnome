package common

import "base:runtime"
import json "core:encoding/json"
import "core:math"
import "core:mem"
import "core:testing"

fail_allocation :: proc(data: rawptr, mode: runtime.Allocator_Mode, size,alignment: int, old_memory: rawptr, old_size: int, loc: runtime.Source_Code_Location) -> ([]u8,runtime.Allocator_Error) {
    if mode==.Alloc || mode==.Resize { return nil,.Out_Of_Memory }
    return nil,nil
}

expect_json :: proc(t: ^testing.T,source,expected: string,indented: bool=false) {
    value,err:=json.parse_string(source,spec=.JSON,parse_integers=false,allocator=context.temp_allocator)
    testing.expect_value(t,err,json.Error.None)
    result,write_error:=stringify(value,indented)
    defer delete(result)
    testing.expect(t,write_error==nil)
    testing.expect_value(t,result,expected)
}
@(test)
json_strings_numbers :: proc(t: ^testing.T) {
    expect_json(t,`{"z":"é😀","a":"\"\\\b\f\n\r\t\u0001"}`,`{"a":"\"\\\b\f\n\r\t\u0001","z":"é😀"}`)
    for pair in ([][2]string{{"1.0","1"},{"-0.0","0"},{"1e-7","1e-07"},{"0.5","0.5"},{"1e20","1e+20"},{"1.0000001e-7","1.0000001e-07"},{"9007199254740991","9007199254740991"}}) { expect_json(t,pair[0],pair[1]) }
    promoted:Writer
    number(&promoted,f64(f32(.1)))
    testing.expect_value(t,finish(&promoted),"0.10000000149011612")
    destroy(&promoted)
    w:Writer
    number(&w,math.INF_F64); put(&w,","); number(&w,math.QNAN_F64)
    testing.expect_value(t,finish(&w),"null,null"); destroy(&w)
    value,err:=stringify(json.Value(json.Integer(-42)))
    testing.expect(t,err==nil); testing.expect_value(t,value,"-42"); delete(value)
}
@(test)
json_utf16_order :: proc(t: ^testing.T) {
    expect_json(t,`{"\ue000":1,"😀":2,"é":3,"a":4}`,"{\"a\":4,\"é\":3,\"😀\":2,\"\ue000\":1}")
    testing.expect(t,utf16_less("😀","\ue000"))
    testing.expect(t,!utf16_less("same","same"))
    testing.expect(t,utf16_less("a","aa"))
}
@(test)
json_indented_layout :: proc(t: ^testing.T) {
    expect_json(t,`{"b":[1,{}],"a":[]}`,"{\n    \"a\": [\n    ],\n    \"b\": [\n        1,\n        {\n        }\n    ]\n}\n",true)
    expect_json(t,"[]","[\n]\n",true)
    expect_json(t,"{}","{\n}\n",true)
}
@(test)
json_allocation_failure :: proc(t: ^testing.T) {
    w:Writer
    old:=context.allocator
    context.allocator={procedure=fail_allocation}
    put(&w,"cannot allocate")
    context.allocator=old
    testing.expect_value(t,w.error,Error("Out of memory"))
    destroy(&w)
}
@(test)
output_defaults :: proc(t: ^testing.T) {
    s:=DEFAULT_OUTPUT_SETTINGS
    testing.expect(t,s.shader_enabled && !s.color_enabled && !adjusts_color(s))
    s.color_enabled=true; testing.expect(t,!adjusts_color(s))
    s.gamma=2; testing.expect(t,adjusts_color(s))
}

@(test)
json_document_compatibility :: proc(t: ^testing.T) {
    value,err:=parse_json(`{"":1,"duplicate":{"old":[1]},"duplicate":{"new":2}}`)
    testing.expect(t,err==nil)
    rendered,write_error:=stringify(value)
    testing.expect(t,write_error==nil)
    testing.expect_value(t,rendered,`{"":1,"duplicate":{"new":2}}`)
    delete(rendered); json.destroy_value(value)
    escaped,escape_error:=parse_json(`{"a":"\q","emoji":"\ud83d\ude00"}`)
    testing.expect(t,escape_error==nil)
    escaped_object:=escaped.(json.Object)
    testing.expect_value(t,string(escaped_object["a"].(json.String)),"q")
    testing.expect_value(t,string(escaped_object["emoji"].(json.String)),"😀")
    json.destroy_value(escaped)
    for pair in ([][2]string{{`{} []`,"garbage at the end of the document"},{`{"a":`,"illegal value"},{`[1,]`,"illegal value"},{`{"a" 1}`,"missing name separator"},{`{"a":1 "b":2}`,"unterminated object"},{`{"a":1,}`,"object is missing after a comma"}}) {
        tracking:mem.Tracking_Allocator
        mem.tracking_allocator_init(&tracking,context.allocator)
        _,failure:=parse_json(pair[0],mem.tracking_allocator(&tracking))
        testing.expect_value(t,failure,Error(pair[1]))
        testing.expect_value(t,tracking.current_memory_allocated,i64(0))
        mem.tracking_allocator_destroy(&tracking)
    }
    nested,allocation_error:=make([]u8,2050)
    testing.expect(t,allocation_error==nil)
    defer delete(nested)
    for i in 0..<1025 { nested[i]='['; nested[len(nested)-1-i]=']' }
    _,depth_error:=parse_json(string(nested))
    testing.expect_value(t,depth_error,Error("too deeply nested document"))
    old:=context.allocator
    context.allocator={procedure=fail_allocation}
    _,allocation_failure:=parse_json(`{"key":["value"]}`)
    context.allocator=old
    testing.expect_value(t,allocation_failure,Error("Out of memory"))
}
