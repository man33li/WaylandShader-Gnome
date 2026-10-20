package common

import "core:fmt"
import json "core:encoding/json"
import "core:mem"
import "core:testing"

// Native schema errors are recorded separately from parser failures in this oracle.
@(test)
json_parser_native_corpus :: proc(t: ^testing.T) {
    corpus,load_error:=json.parse_string(string(#load("../tests/parser-corpus-baseline.json")),spec=.JSON,parse_integers=false)
    testing.expect_value(t,load_error,json.Error.None)
    if load_error!=.None { return }
    defer json.destroy_value(corpus)
    for entry in corpus.(json.Array) {
        object:=entry.(json.Object)
        id:=string(object["id"].(json.String))
        source:=string(object["source"].(json.String))
        // This oracle enters through native QString::fromUtf8 before the JSON parser.
        if len(source)>=3 && source[:3]=="\xef\xbb\xbf" { source=source[3:] }
        expected:=string(object["parseError"].(json.String))
        tracking:mem.Tracking_Allocator
        mem.tracking_allocator_init(&tracking,context.allocator)
        value,err:=parse_json(source,mem.tracking_allocator(&tracking))
        actual:=""
        if message,failed:=err.?; failed { actual=message }
        if actual!=expected { fmt.eprintf("parser corpus %s: %q != %q\n",id,actual,expected) }
        testing.expect_value(t,actual,expected)
        if err==nil { destroy_document(&value) }
        if tracking.current_memory_allocated!=0 { fmt.eprintf("parser corpus allocation %s\n",id) }
        testing.expect_value(t,tracking.current_memory_allocated,i64(0))
        mem.tracking_allocator_destroy(&tracking)
    }
    // Raw invalid bytes cannot pass the native guard; escaped multibyte cases are in the native corpus.
    for source in ([]string{"{\"a\":\"\xff\"}","{\"a\":\"\\q\xff\"}","{\"a\":\"\xc0\xaf\"}"}) {
        _,err:=parse_json(source)
        testing.expect_value(t,err,Error("invalid UTF8 string"))
    }
}
