package common

import json "core:encoding/json"
import "core:math"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

Error :: Maybe(string)
Writer :: struct { bytes: [dynamic]u8, error: Error, indented: bool }
put :: proc(b: ^Writer, s: string) {
    if b.error != nil { return }
    if _, err := append(&b.bytes, ..transmute([]u8)s); err != nil { b.error = "Out of memory" }
}
quote :: proc(b: ^Writer, s: string) {
    put(b,"\"")
    for c in transmute([]u8)s {
        switch c {
        case '"': put(b,"\\\"")
        case '\\': put(b,"\\\\")
        case '\b': put(b,"\\b")
        case '\f': put(b,"\\f")
        case '\n': put(b,"\\n")
        case '\r': put(b,"\\r")
        case '\t': put(b,"\\t")
        case:
            if c < 32 { digits := "0123456789abcdef"; escaped := [6]u8{'\\','u','0','0',digits[c>>4],digits[c&15]}; put(b,string(escaped[:])) }
            else { byte := [1]u8{c}; put(b,string(byte[:])) }
        }
    }
    put(b,"\"")
}
shortest_float :: proc(buffer: []u8,n: f64) -> string {
    // The pinned shortest formatter retains extra digits for some f32-promoted values.
    precision:=1
    for precision<17 {
        candidate:=strconv.write_float(buffer,n,'e',precision-1,64)
        parsed,ok:=strconv.parse_f64(candidate)
        if ok && parsed==n { break }
        precision+=1
    }
    text:=strconv.write_float(buffer,n,'e',precision-1,64)
    exponent_at:=strings.index_byte(text,'e')
    exponent,_:=strconv.parse_int(text[exponent_at+1:])
    if exponent>=-4 && exponent<6 { text=strconv.write_float(buffer,n,'f',precision-1-exponent,64) }
    if len(text)>0 && text[0]=='+' { text=text[1:] }
    return text
}
number :: proc(b: ^Writer, n: f64) {
    if math.is_nan(n) || math.is_inf(n) { put(b,"null"); return }
    buffer: [64]u8
    if n >= -9223372036854775808.0 && n < 9223372036854775808.0 && math.trunc(n) == n { put(b,strconv.write_int(buffer[:],i64(n),10)); return }
    put(b,shortest_float(buffer[:],n))
}
boolean :: proc(b: ^Writer, value: bool) { put(b,"true" if value else "false") }
indentation :: proc(b: ^Writer, count: int) { for _ in 0..<count { put(b," ") } }
Utf16_Iterator :: struct { remaining: string, pending: u16 }
next_utf16 :: proc(it: ^Utf16_Iterator) -> (u16,bool) {
    if it.pending != 0 { result := it.pending; it.pending=0; return result,true }
    if len(it.remaining)==0 { return 0,false }
    code, width := utf8.decode_rune(it.remaining)
    it.remaining = it.remaining[width:]
    if code < 0x10000 { return u16(code),true }
    value := u32(code)-0x10000
    it.pending = u16(0xdc00+(value&0x3ff))
    return u16(0xd800+(value>>10)),true
}
utf16_less :: proc(a,b: string) -> bool {
    left,right := Utf16_Iterator{remaining=a},Utf16_Iterator{remaining=b}
    for { x,more_x := next_utf16(&left); y,more_y := next_utf16(&right); if !more_x || !more_y { return !more_x && more_y }; if x!=y { return x<y } }
}
write_value :: proc(b: ^Writer, value: json.Value, indent: int = -1) -> Error {
    b.indented = indent >= 0
    switch v in value {
    case json.Null: put(b,"null")
    case json.Boolean: boolean(b,bool(v))
    case json.Integer: buffer:[32]u8; put(b,strconv.write_int(buffer[:],i64(v),10))
    case json.Float: number(b,f64(v))
    case json.String: quote(b,string(v))
    case json.Array:
        put(b,"[")
        if indent>=0 { put(b,"\n") }
        for item,i in v {
            if i>0 { put(b,",\n" if indent>=0 else ",") }
            if indent>=0 { indentation(b,indent+4) }
            write_value(b,item,indent+4 if indent>=0 else -1)
        }
        if indent>=0 { if len(v)>0 { put(b,"\n") }; indentation(b,indent) }
        put(b,"]")
    case json.Object:
        keys,err := make([]string,len(v),context.temp_allocator)
        if err != nil { b.error="Out of memory"; return b.error }
        i:=0
        for key in v { keys[i]=key; i+=1 }
        slice.sort_by(keys,utf16_less)
        put(b,"{")
        if indent>=0 { put(b,"\n") }
        for key,index in keys {
            if index>0 { put(b,",\n" if indent>=0 else ",") }
            if indent>=0 { indentation(b,indent+4) }
            quote(b,key); put(b,": " if indent>=0 else ":")
            write_value(b,v[key],indent+4 if indent>=0 else -1)
        }
        if indent>=0 { if len(keys)>0 { put(b,"\n") }; indentation(b,indent) }
        put(b,"}")
    }
    return b.error
}
finish :: proc(b: ^Writer) -> string { if b.indented { put(b,"\n"); b.indented=false }; return string(b.bytes[:]) }
destroy :: proc(b: ^Writer) { delete(b.bytes); b^={} }
stringify :: proc(value: json.Value, indented: bool = false) -> (string,Error) {
    b:Writer
    write_value(&b,value,0 if indented else -1)
    result:=finish(&b)
    if b.error!=nil { err:=b.error; destroy(&b); return "",err }
    return result,nil
}
