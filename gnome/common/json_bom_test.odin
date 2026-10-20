package common

import json "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:testing"

// Original C++ captures cover raw/escaped, double/middle BOMs, later escapes and both duplicate orders.
@(test)
json_bom_baseline_keys :: proc(t: ^testing.T) {
    corpus,load_error:=json.parse_string(string(#load("../tests/bom-contract-baseline.json")),spec=.JSON,parse_integers=false)
    if !testing.expect_value(t,load_error,json.Error.None) { return }
    defer json.destroy_value(corpus)
    checked:=0
    for record in corpus.(json.Array) {
        row:=record.(json.Object)
        id:=string(row["id"].(json.String))
        if !strings.has_prefix(id,"param-name:") && !strings.has_prefix(id,"collide-param-name:") { continue }
        source:=string(row["steps"].(json.Array)[0].(json.Array)[1].(json.String))
        document,err:=parse_json(source)
        if !testing.expect(t,err==nil,id) { continue }
        defer destroy_document(&document)
        names:=document.value.(json.Object)["parameters"].(json.Object)["/p"].(json.Object)
        keys:=make([]string,len(names),context.temp_allocator)
        at:=0; for name in names { keys[at]=name; at+=1 }; slice.sort_by(keys,utf16_less)
        actual:map[string]f64
        defer delete(actual)
        invalid:=false
        for raw_name in keys {
            name:=json_text(&document,raw_name)
            if name=="" { invalid=true; break }
            actual[name]=f64(names[raw_name].(json.Float))
        }
        outcome:=row["results"].(json.Array)[0].(json.Object)
        if _,failed:=outcome["error"]; failed {
            testing.expect(t,invalid,id)
        } else {
            testing.expect(t,!invalid,id)
            expected,expected_error:=json.parse_string(string(row["settings"].(json.String)),spec=.JSON,parse_integers=false)
            if !testing.expect_value(t,expected_error,json.Error.None) { continue }
            defer json.destroy_value(expected)
            values:=expected.(json.Object)["parameters"].(json.Object)["/p"].(json.Object)
            testing.expect(t,len(actual)==len(values),id)
            for name,value in values {
                got,present:=actual[name]
                testing.expect(t,present,id)
                testing.expect(t,got==f64(value.(json.Float)),id)
            }
        }
        checked+=1
    }
    testing.expect_value(t,checked,68)
}

@(test)
json_bom_values_lookup_writer :: proc(t: ^testing.T) {
    b::"\xef\xbb\xbf"
    for pair in ([][2]string{
        {b+"GAIN","GAIN"}, {`\ufeffGAIN`,b+"GAIN"}, {b+b+"GAIN",b+"GAIN"},
        {"GA"+b+"IN","GA"+b+"IN"}, {b+`\u0047AIN`,b+"GAIN"},
        {b+`G\ufeffAIN`,b+"G"+b+"AIN"}, {b,""}, {`\ufeff`,b},
        {`\ud800`,"\xed\xa0\x80"},
    }) {
        document,err:=parse_json(fmt.tprintf(`["%s"]`,pair[0]))
        if !testing.expect(t,err==nil) { continue }
        defer destroy_document(&document)
        value,ok:=json_string_value(&document,document.value.(json.Array)[0])
        testing.expect(t,ok)
        testing.expect_value(t,value,pair[1])
        rendered,write_error:=stringify(document.value,document=&document)
        testing.expect(t,write_error==nil)
        expected:Writer
        put(&expected,"["); quote(&expected,pair[1]); put(&expected,"]")
        testing.expect_value(t,rendered,finish(&expected))
        delete(rendered); destroy(&expected)
    }
    source::`{"enabled":false,"`+b+`enabled":true,"\ufeffversion":2,"version":1}`
    document,err:=parse_json(source)
    if !testing.expect(t,err==nil,fmt.tprintf("source %q: %v",source,err)) { return }
    defer destroy_document(&document)
    object:=document.value.(json.Object)
    testing.expect_value(t,len(object),4)
    testing.expect_value(t,bool(object["enabled"].(json.Boolean)),false)
    testing.expect_value(t,f64(object["version"].(json.Float)),f64(1))
    testing.expect_value(t,bool(object[b+"enabled"].(json.Boolean)),true)
}

@(test)
json_document_provenance_ownership :: proc(t: ^testing.T) {
    tracking:mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking,context.allocator)
    defer mem.tracking_allocator_destroy(&tracking)
    document,err:=parse_json(`{"key":{"old":["value"]},"key":{"new":"\ufeffvalue"},"empty":0,"empty":1}`,mem.tracking_allocator(&tracking))
    if !testing.expect(t,err==nil) { return }
    // Only live string allocations retain metadata after nested duplicate disposal.
    testing.expect_value(t,len(document.string_encoding),4)
    value,ok:=json_string_value(&document,document.value.(json.Object)["key"].(json.Object)["new"])
    testing.expect(t,ok)
    testing.expect_value(t,value,"\xef\xbb\xbfvalue")
    // Destruction restores the parse allocator even though this scope uses the normal allocator.
    destroy_document(&document)
    testing.expect_value(t,tracking.current_memory_allocated,i64(0))
}
