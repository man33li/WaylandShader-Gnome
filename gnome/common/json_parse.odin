package common

import "base:runtime"
import json "core:encoding/json"
import "core:math"
import "core:strconv"
import "core:unicode/utf8"

JSON_String_Encoding :: enum { UTF8, UTF16 }
JSON_Document :: struct {
    value: json.Value,
    string_encoding: map[rawptr]JSON_String_Encoding,
    allocator: runtime.Allocator,
}
destroy_document :: proc(document: ^JSON_Document) {
    allocator:=document.allocator
    if allocator.procedure==nil { allocator=context.allocator }
    json.destroy_value(document.value,allocator)
    delete(document.string_encoding)
    document^={}
}
json_text :: proc(document: ^JSON_Document, value: string) -> string {
    if document!=nil {
        encoding,parsed:=document.string_encoding[rawptr(raw_data(value))]
        if parsed && encoding==.UTF8 && len(value)>=3 && value[:3]=="\xef\xbb\xbf" { return value[3:] }
    }
    return value
}
json_string_value :: proc(document: ^JSON_Document, value: json.Value) -> (string,bool) {
    text,ok:=value.(json.String)
    if !ok { return "",false }
    return json_text(document,string(text)),true
}

// Qt 6.11.2 stores a whole string as UTF-16 if any escape occurs, including after a raw BOM.
JSON_Parser :: struct { source: string, index: int, depth: int, string_encoding: map[rawptr]JSON_String_Encoding }
json_delete_string :: proc(p: ^JSON_Parser, value: string) {
    delete_key(&p.string_encoding,rawptr(raw_data(value)))
    delete(value)
}
json_delete_node :: proc(p: ^JSON_Parser, value: json.Value) {
    #partial switch v in value {
    case json.String: json_delete_string(p,string(v))
    case json.Array:
        for item in v { json_delete_node(p,item) }
        delete(v)
    case json.Object:
        for key,item in v { json_delete_string(p,key); json_delete_node(p,item) }
        delete(v)
    }
}
json_digit :: proc(c: u8) -> bool { return c>='0' && c<='9' }
json_hex :: proc(source: string) -> (u32,bool) {
    value:u32
    for c in transmute([]u8)source {
        value<<=4
        if c>='0' && c<='9' { value+=u32(c-'0') }
        else if c>='a' && c<='f' { value+=u32(c-'a'+10) }
        else if c>='A' && c<='F' { value+=u32(c-'A'+10) }
        else { return 0,false }
    }
    return value,true
}
json_space :: proc(p: ^JSON_Parser) -> bool {
    s:=p.source
    for p.index<len(s) && (s[p.index]==' ' || s[p.index]=='\t' || s[p.index]=='\n' || s[p.index]=='\r') { p.index+=1 }
    return p.index<len(s)
}
json_next :: proc(p: ^JSON_Parser) -> u8 {
    if !json_space(p) { return 0 }
    c:=p.source[p.index]; p.index+=1
    switch c {
    case '{','}','[',']',':',',','"': return c
    }
    return 0
}
json_string :: proc(p: ^JSON_Parser) -> (string,Error) {
    source:=p.source
    end:=p.index
    encoding:=JSON_String_Encoding.UTF8
    for end<len(source) && source[end]!='"' {
        if source[end]=='\\' { encoding=.UTF16; if end+1<len(source) { end+=1 } }
        end+=1
    }
    bytes,err:=make([]u8,end-p.index)
    if err!=nil { return "","Out of memory" }
    success:=false
    defer if !success { delete(bytes) }
    count:=0
    for p.index<len(source) {
        c:=source[p.index]; p.index+=1
        if c=='"' {
            text:=string(bytes[:count])
            if count>0 && map_insert(&p.string_encoding,rawptr(raw_data(text)),encoding)==nil { return "","Out of memory" }
            success=true
            return text,nil
        }
        if c!='\\' {
            if c>=0x80 {
                code,width:=utf8.decode_rune(source[p.index-1:])
                if code==0xfffd && width==1 { return "","invalid UTF8 string" }
                copy(bytes[count:],source[p.index-1:p.index-1+width]); count+=width; p.index+=width-1
            } else { bytes[count]=c; count+=1 }
            continue
        }
        if p.index>=len(source) { return "","invalid escape sequence" }
        c=source[p.index]; p.index+=1
        switch c {
        case 'b': bytes[count]='\b'
        case 'f': bytes[count]='\f'
        case 'n': bytes[count]='\n'
        case 'r': bytes[count]='\r'
        case 't': bytes[count]='\t'
        case 'u':
            if len(source)-p.index<4 { return "","invalid escape sequence" }
            code,ok:=json_hex(source[p.index:p.index+4])
            if !ok { return "","invalid escape sequence" }
            p.index+=4
            if code>=0xd800 && code<=0xdbff && len(source)-p.index>=6 && source[p.index:p.index+2]=="\\u" {
                low,valid:=json_hex(source[p.index+2:p.index+6])
                if valid && low>=0xdc00 && low<=0xdfff { code=0x10000+((code-0xd800)<<10)+(low-0xdc00); p.index+=6 }
            }
            encoded,width:=text_encode(rune(code))
            copy(bytes[count:],encoded[:width]); count+=width
            continue
        case: bytes[count]=c
        }
        count+=1
    }
    return "","unterminated string"
}
json_number :: proc(p: ^JSON_Parser) -> (json.Value,Error) {
    s:=p.source; start:=p.index
    if p.index<len(s) && s[p.index]=='-' { p.index+=1 }
    if p.index<len(s) && s[p.index]=='0' { p.index+=1 }
    else { for p.index<len(s) && json_digit(s[p.index]) { p.index+=1 } }
    if p.index<len(s) && s[p.index]=='.' {
        p.index+=1
        for p.index<len(s) && json_digit(s[p.index]) { p.index+=1 }
    }
    if p.index<len(s) && (s[p.index]=='e' || s[p.index]=='E') {
        p.index+=1
        if p.index<len(s) && (s[p.index]=='+' || s[p.index]=='-') { p.index+=1 }
        for p.index<len(s) && json_digit(s[p.index]) { p.index+=1 }
    }
    text:=s[start:p.index]
    value,ok:=strconv.parse_f64(text)
    if !ok || math.is_nan(value) || math.is_inf(value) { return {},"illegal number" }
    if value==0 {
        for c in transmute([]u8)text {
            if c=='e' || c=='E' { break }
            if c>='1' && c<='9' { return {},"illegal number" }
        }
    }
    return json.Float(value),nil
}
json_node :: proc(p: ^JSON_Parser) -> (json.Value,Error) {
    if !json_space(p) { return {},"illegal value" }
    c:=p.source[p.index]; p.index+=1
    switch c {
    case 'n','t','f':
        word:="null"
        if c=='t' { word="true" }
        if c=='f' { word="false" }
        start:=p.index-1
        if len(p.source)-start<len(word) || p.source[start:start+len(word)]!=word { return {},"illegal value" }
        p.index=start+len(word)
        if c=='n' { return json.Null{},nil }
        return json.Boolean(c=='t'),nil
    case '"':
        value,err:=json_string(p)
        if err!=nil { return {},err }
        return json.String(value),nil
    case '{':
        if p.depth>=1024 { return {},"too deeply nested document" }
        p.depth+=1; defer p.depth-=1
        obj:json.Object
        success:=false
        defer if !success { json_delete_node(p,json.Value(obj)) }
        token:=json_next(p)
        for token=='"' {
            key,err:=json_string(p)
            if err!=nil { return {},err }
            key_owned:=true
            defer if key_owned { json_delete_string(p,key) }
            if json_next(p)!=':' { return {},"missing name separator" }
            if !json_space(p) { return {},"unterminated object" }
            value,ve:=json_node(p)
            if ve!=nil { return {},ve }
            stored,entry,inserted,allocation_error:=map_entry(cast(^map[string]json.Value)&obj,key)
            if allocation_error!=nil { json_delete_node(p,value); return {},"Out of memory" }
            if !inserted {
                // map_entry retains the stored key; Qt retains the last duplicate's encoding.
                if len(key)>0 { p.string_encoding[rawptr(raw_data(stored^))]=p.string_encoding[rawptr(raw_data(key))] }
                json_delete_node(p,entry^)
            } else { key_owned=false }
            entry^=value
            token=json_next(p)
            if token!=',' { break }
            token=json_next(p)
            if token=='}' { return {},"object is missing after a comma" }
        }
        if token!='}' { return {},"unterminated object" }
        success=true
        return obj,nil
    case '[':
        if p.depth>=1024 { return {},"too deeply nested document" }
        p.depth+=1; defer p.depth-=1
        array:json.Array
        success:=false
        defer if !success { json_delete_node(p,json.Value(array)) }
        if !json_space(p) { return {},"unterminated array" }
        if p.source[p.index]==']' { p.index+=1; success=true; return array,nil }
        for {
            if !json_space(p) { return {},"unterminated array" }
            value,err:=json_node(p)
            if err!=nil { return {},err }
            if _,ae:=append(&array,value); ae!=nil { json_delete_node(p,value); return {},"Out of memory" }
            token:=json_next(p)
            if token==']' { break }
            if token!=',' {
                if !json_space(p) { return {},"unterminated array" }
                return {},"missing value separator"
            }
        }
        success=true
        return array,nil
    case ',': return {},"illegal value"
    case '}',']': return {},"object is missing after a comma"
    case:
        p.index-=1
        return json_number(p)
    }
}
parse_json :: proc(source: string,allocator:=context.allocator) -> (JSON_Document,Error) {
    context.allocator=allocator
    p:=JSON_Parser{source=source}
    success:=false
    defer if !success { delete(p.string_encoding) }
    // The caller has already performed any QString/C-string decoding.
    if len(source)>3 && source[:3]=="\xef\xbb\xbf" { p.index=3 }
    result,err:=json_node(&p)
    if err!=nil { return {},err }
    if json_space(&p) { json_delete_node(&p,result); return {},"garbage at the end of the document" }
    #partial switch _ in result {
    case json.Object,json.Array:
        success=true
        return {value=result,string_encoding=p.string_encoding,allocator=allocator},nil
    }
    json_delete_node(&p,result)
    return {},"illegal value"
}
