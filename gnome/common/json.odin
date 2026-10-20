package common

import json "core:encoding/json"
import "core:math"
import "core:slice"
import "core:strconv"
import "core:strings"

Error :: Maybe(string)
Writer :: struct { bytes: [dynamic]u8, error: Error, indented: bool }
put :: proc(b: ^Writer, s: string) {
    if b.error != nil { return }
    if _, err := append(&b.bytes, ..transmute([]u8)s); err != nil { b.error = "Out of memory" }
}
quote :: proc(b: ^Writer, s: string) {
    put(b,"\"")
    for i:=0; i<len(s); {
        c,width:=text_decode(s,i)
        i+=width
        switch c {
        case '"': put(b,"\\\"")
        case '\\': put(b,"\\\\")
        case '\b': put(b,"\\b")
        case '\f': put(b,"\\f")
        case '\n': put(b,"\\n")
        case '\r': put(b,"\\r")
        case '\t': put(b,"\\t")
        case:
            if c < 32 || c>=0xd800 && c<=0xdfff {
                digits := "0123456789abcdef"
                escaped := [6]u8{'\\','u',digits[(c>>12)&15],digits[(c>>8)&15],digits[(c>>4)&15],digits[c&15]}
                put(b,string(escaped[:]))
            } else if c==0xfffd && width==1 { put(b,"�") }
            else { put(b,s[i-width:i]) }
        }
    }
    put(b,"\"")
}
shortest_float :: proc(buffer: []u8,n: f64) -> string {
    // Find shortest round-tripping digits, then apply Qt qlocale_tools.cpp resolveFormat.
    scientific:[32]u8
    precision:=1
    for precision<17 {
        candidate:=strconv.write_float(scientific[:],n,'e',precision-1,64)
        parsed,ok:=strconv.parse_f64(candidate)
        if ok && parsed==n { break }
        precision+=1
    }
    text:=strconv.write_float(scientific[:],n,'e',precision-1,64)
    if len(text)>0 && text[0]=='+' { text=text[1:] }
    exponent_at:=strings.index_byte(text,'e')
    exponent,_:=strconv.parse_int(text[exponent_at+1:])
    decimal:=exponent+1
    bias:=4
    if precision<=decimal && precision>1 { bias+=1 }
    else if precision==1 && decimal<=0 { bias-=1 }
    fixed:=1-decimal<=bias if decimal<=0 else decimal<=precision+bias
    if !fixed { copy(buffer,transmute([]u8)text); return string(buffer[:len(text)]) }
    digits:[17]u8
    count:=0
    for c in text[:exponent_at] { if c>='0' && c<='9' { digits[count]=u8(c); count+=1 } }
    length:=0
    if n<0 { buffer[length]='-'; length+=1 }
    if decimal<=0 {
        buffer[length]='0'; buffer[length+1]='.'; length+=2
        for _ in 0..<-decimal { buffer[length]='0'; length+=1 }
        copy(buffer[length:],digits[:count]); length+=count
    } else {
        for i in 0..<max(decimal,count) {
            if i==decimal { buffer[length]='.'; length+=1 }
            buffer[length]=digits[i] if i<count else '0'; length+=1
        }
    }
    return string(buffer[:length])
}
number :: proc(b: ^Writer, n: f64) {
    if math.is_nan(n) || math.is_inf(n) { put(b,"null"); return }
    buffer: [64]u8
    // QJsonValue(double) avoids upgrading precision beyond double's integer mantissa.
    if n >= -9007199254740992.0 && n <= 9007199254740992.0 && math.trunc(n) == n { put(b,strconv.write_int(buffer[:],i64(n),10)); return }
    put(b,shortest_float(buffer[:],n))
}
boolean :: proc(b: ^Writer, value: bool) { put(b,"true" if value else "false") }
indentation :: proc(b: ^Writer, count: int) { for _ in 0..<count { put(b," ") } }
Utf16_Iterator :: struct { remaining: string, pending: u16 }
next_utf16 :: proc(it: ^Utf16_Iterator) -> (u16,bool) {
    if it.pending != 0 { result := it.pending; it.pending=0; return result,true }
    if len(it.remaining)==0 { return 0,false }
    code, width := text_decode(it.remaining,0)
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
write_value :: proc(b: ^Writer, value: json.Value, indent: int = -1, document: ^JSON_Document = nil) -> Error {
    b.indented = indent >= 0
    switch v in value {
    case json.Null: put(b,"null")
    case json.Boolean: boolean(b,bool(v))
    case json.Integer: buffer:[32]u8; put(b,strconv.write_int(buffer[:],i64(v),10))
    case json.Float: number(b,f64(v))
    case json.String: quote(b,json_text(document,string(v)))
    case json.Array:
        put(b,"[")
        if indent>=0 { put(b,"\n") }
        for item,i in v {
            if i>0 { put(b,",\n" if indent>=0 else ",") }
            if indent>=0 { indentation(b,indent+4) }
            write_value(b,item,indent+4 if indent>=0 else -1,document)
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
            quote(b,json_text(document,key)); put(b,": " if indent>=0 else ":")
            write_value(b,v[key],indent+4 if indent>=0 else -1,document)
        }
        if indent>=0 { if len(keys)>0 { put(b,"\n") }; indentation(b,indent) }
        put(b,"}")
    }
    return b.error
}
finish :: proc(b: ^Writer) -> string { if b.indented { put(b,"\n"); b.indented=false }; return string(b.bytes[:]) }
destroy :: proc(b: ^Writer) { delete(b.bytes); b^={} }
stringify :: proc(value: json.Value, indented: bool = false, document: ^JSON_Document = nil) -> (string,Error) {
    b:Writer
    write_value(&b,value,0 if indented else -1,document)
    result:=finish(&b)
    if b.error!=nil { err:=b.error; destroy(&b); return "",err }
    return result,nil
}
