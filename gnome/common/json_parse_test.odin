package common

import json "core:encoding/json"
import "core:mem"
import "core:testing"

// Error strings and accepted forms are pinned by native-rework-baseline.json.
@(test)
json_parser_rework_errors :: proc(t: ^testing.T) {
    for pair in ([][2]string{
        {`{"version":1,"ignored":1e-4000}`,"illegal number"},
        {`{"version":1,"ignored":1e4000}`,"illegal number"},
        {`{"version":1,"ignored":"\u+123"}`,"invalid escape sequence"},
        {`{"version":1,"ignored":"\u 123"}`,"invalid escape sequence"},
        {`{"version":1,"ignored":"\ué123"}`,"invalid escape sequence"},
        {`{"version":}`,"object is missing after a comma"},
        {`{"version":01}`,"unterminated object"},
        {`[01]`,"missing value separator"},
        {`{"version":1,"ignored":truefalse}`,"unterminated object"},
        {`{"a":`,"unterminated object"},
        {`[1,]`,"object is missing after a comma"},
        {`{"a":[}`,"object is missing after a comma"},
        {"not json","illegal value"},
    }) {
        tracking:mem.Tracking_Allocator
        mem.tracking_allocator_init(&tracking,context.allocator)
        _,err:=parse_json(pair[0],mem.tracking_allocator(&tracking))
        testing.expect_value(t,err,Error(pair[1]))
        testing.expect_value(t,tracking.current_memory_allocated,i64(0))
        mem.tracking_allocator_destroy(&tracking)
    }
}
@(test)
json_parser_rework_strings :: proc(t: ^testing.T) {
    for pair in ([][2]string{
        {`{"version":1.}`,`{"version":1}`},
        {"{\"ignored\":\"a\nb\"}",`{"ignored":"a\nb"}`},
        {`{"path":"/x\ud800.slangp"}`,`{"path":"/x\ud800.slangp"}`},
        {`{"path":"/x\udfff.slangp"}`,`{"path":"/x\udfff.slangp"}`},
        {`{"pair":"\ud83d\ude00"}`,`{"pair":"😀"}`},
    }) {
        value,err:=parse_json(pair[0])
        testing.expect(t,err==nil)
        if err!=nil { continue }
        rendered,we:=stringify(value.value,document=&value)
        testing.expect(t,we==nil)
        testing.expect_value(t,rendered,pair[1])
        delete(rendered); destroy_document(&value)
    }
    value,err:=parse_json(`{"high":"\ud800","low":"\udfff"}`)
    testing.expect(t,err==nil)
    if err==nil {
        object:=value.value.(json.Object)
        testing.expect_value(t,string(object["high"].(json.String)),"\xed\xa0\x80")
        testing.expect_value(t,string(object["low"].(json.String)),"\xed\xbf\xbf")
        destroy_document(&value)
    }
}
@(test)
text_internal_external_boundaries :: proc(t: ^testing.T) {
    for pair in ([][2]string{{"a\xffb","a�b"},{"a\xed\xa0\x80b","a�b"},{"é😀","é😀"}}) {
        converted,err:=text_utf8(pair[0])
        testing.expect(t,err==nil)
        testing.expect_value(t,converted,pair[1])
        delete(converted)
    }
    converted,err:=text_utf8("rawbad\xff.slangp",internal=false)
    testing.expect(t,err==nil)
    testing.expect_value(t,converted,"rawbad�.slangp")
    delete(converted)
    old:=context.allocator
    context.allocator={procedure=fail_allocation}
    _,allocation_error:=text_utf8("cannot allocate")
    context.allocator=old
    testing.expect_value(t,allocation_error,Error("Out of memory"))
}
