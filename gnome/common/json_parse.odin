package common

import json "core:encoding/json"
import "core:math"
import "core:strconv"
import "core:unicode/utf8"

JSON_Parser :: struct { source: string, index: int, token: json.Token, error: Error, depth: int }
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
json_next :: proc(p: ^JSON_Parser) {
    if p.error!=nil { return }
    s:=p.source
    for p.index<len(s) && (s[p.index]==' ' || s[p.index]=='\t' || s[p.index]=='\n' || s[p.index]=='\r') { p.index+=1 }
    if p.index==len(s) { p.token={kind=.EOF}; return }
    start:=p.index; p.index+=1
    c:=s[start]
    p.token={kind=.Invalid}
    switch c {
    case '{': p.token.kind=.Open_Brace
    case '}': p.token.kind=.Close_Brace
    case '[': p.token.kind=.Open_Bracket
    case ']': p.token.kind=.Close_Bracket
    case ':': p.token.kind=.Colon
    case ',': p.token.kind=.Comma
    case '"':
        p.token.kind=.String
        for p.index<len(s) {
            current:=s[p.index]; p.index+=1
            if current=='"' { p.token.text=s[start:p.index]; return }
            if current=='\\' && p.index<len(s) { p.index+=1 }
        }
        p.error="unterminated string"
    case 't','f','n':
        word:="true"; p.token.kind=.True
        if c=='f' { word="false"; p.token.kind=.False }
        if c=='n' { word="null"; p.token.kind=.Null }
        if len(s)-start>=len(word) && s[start:start+len(word)]==word { p.index=start+len(word) }
        else { p.error="illegal value" }
    case '-','0','1','2','3','4','5','6','7','8','9':
        i:=start
        if s[i]=='-' { i+=1 }
        if i>=len(s) || !json_digit(s[i]) { p.error="illegal number"; return }
        if s[i]=='0' { i+=1 } else { for i<len(s) && json_digit(s[i]) { i+=1 } }
        if i<len(s) && s[i]=='.' { i+=1; for i<len(s) && json_digit(s[i]) { i+=1 } }
        if i<len(s) && (s[i]=='e' || s[i]=='E') {
            i+=1
            if i<len(s) && (s[i]=='+' || s[i]=='-') { i+=1 }
            digits:=i
            for i<len(s) && json_digit(s[i]) { i+=1 }
            if i==digits { p.error="illegal number"; return }
        }
        p.index=i; p.token.kind=.Float
    }
    p.token.text=s[start:p.index]
}
json_string :: proc(p: ^JSON_Parser) -> (string,Error) {
    source:=p.token.text
    if len(source)<2 || source[len(source)-1]!='"' { return "","unterminated string" }
    source=source[1:len(source)-1]
    bytes,err:=make([]u8,len(source))
    if err!=nil { return "","Out of memory" }
    success:=false
    defer if !success { delete(bytes) }
    count:=0
    for i:=0; i<len(source); i+=1 {
        c:=source[i]
        if c!='\\' {
            if c>=0x80 {
                code,width:=utf8.decode_rune(source[i:])
                if code==0xfffd && width==1 { return "","invalid UTF8 string" }
                copy(bytes[count:],source[i:i+width]); count+=width; i+=width-1
            } else { bytes[count]=c; count+=1 }
            continue
        }
        i+=1
        if i>=len(source) { return "","unterminated string" }
        c=source[i]
        switch c {
        case 'b': bytes[count]='\b'
        case 'f': bytes[count]='\f'
        case 'n': bytes[count]='\n'
        case 'r': bytes[count]='\r'
        case 't': bytes[count]='\t'
        case 'u':
            if i+4>=len(source) { return "","invalid escape sequence" }
            code,ok:=json_hex(source[i+1:i+5])
            if !ok { return "","invalid escape sequence" }
            i+=4
            if code>=0xd800 && code<=0xdbff && i+6<len(source) && source[i+1:i+3]=="\\u" {
                low,valid:=json_hex(source[i+3:i+7])
                if valid && low>=0xdc00 && low<=0xdfff { code=0x10000+((code-0xd800)<<10)+(low-0xdc00); i+=6 }
            }
            encoded,width:=text_encode(rune(code))
            copy(bytes[count:],encoded[:width]); count+=width
            continue
        case: bytes[count]=c
        }
        count+=1
    }
    json_next(p)
    success=true
    return string(bytes[:count]),nil
}
json_node :: proc(p: ^JSON_Parser) -> (result: json.Value,failure: Error) {
    if p.error!=nil { return {},p.error }
    #partial switch p.token.kind {
    case .Null: json_next(p); return json.Null{},p.error
    case .False: json_next(p); return json.Boolean(false),p.error
    case .True: json_next(p); return json.Boolean(true),p.error
    case .Float,.Integer:
        value,ok:=strconv.parse_f64(p.token.text)
        if !ok || math.is_nan(value) || math.is_inf(value) { return {},"illegal number" }
        if value==0 {
            for c in transmute([]u8)p.token.text {
                if c=='e' || c=='E' { break }
                if c>='1' && c<='9' { return {},"illegal number" }
            }
        }
        json_next(p)
        return json.Float(value),p.error
    case .String:
        value,err:=json_string(p)
        if err!=nil { return {},err }
        if p.error!=nil { delete(value); return {},p.error }
        return json.String(value),nil
    case .Open_Brace:
        if p.depth>=1024 { return {},"too deeply nested document" }
        p.depth+=1; defer p.depth-=1
        obj:json.Object
        success:=false
        defer if !success { json.destroy_value(json.Value(obj)) }
        json_next(p)
        if p.error!=nil { return {},p.error }
        if p.token.kind==.Close_Brace { json_next(p); if p.error!=nil { return {},p.error }; success=true; return obj,nil }
        for {
            if p.token.kind==.EOF { return {},"unterminated object" }
            if p.token.kind!=.String { return {},"object is missing after a comma" }
            key,err:=json_string(p)
            if err!=nil { return {},err }
            key_owned:=true
            defer if key_owned { delete(key) }
            if p.error!=nil { return {},p.error }
            if p.token.kind!=.Colon { return {},"missing name separator" }
            json_next(p)
            if p.token.kind==.EOF { return {},"unterminated object" }
            if p.token.kind==.Close_Brace || p.token.kind==.Close_Bracket { return {},"object is missing after a comma" }
            value,ve:=json_node(p)
            if ve!=nil { return {},ve }
            if previous,exists:=obj[key]; exists { json.destroy_value(previous); obj[key]=value }
            else {
                if map_insert(cast(^map[string]json.Value)&obj,key,value)==nil { json.destroy_value(value); return {},"Out of memory" }
                key_owned=false
            }
            if p.error!=nil { return {},p.error }
            if p.token.kind==.Close_Brace { json_next(p); if p.error!=nil { return {},p.error }; success=true; return obj,nil }
            if p.token.kind==.EOF { return {},"unterminated object" }
            if p.token.kind!=.Comma { return {},"unterminated object" }
            json_next(p)
            if p.error!=nil { return {},p.error }
            if p.token.kind==.Close_Brace { return {},"object is missing after a comma" }
        }
    case .Open_Bracket:
        if p.depth>=1024 { return {},"too deeply nested document" }
        p.depth+=1; defer p.depth-=1
        array:json.Array
        success:=false
        defer if !success { json.destroy_value(json.Value(array)) }
        json_next(p)
        if p.error!=nil { return {},p.error }
        if p.token.kind==.Close_Bracket { json_next(p); if p.error!=nil { return {},p.error }; success=true; return array,nil }
        for {
            if p.token.kind==.EOF { return {},"unterminated array" }
            if p.token.kind==.Close_Brace || p.token.kind==.Close_Bracket { return {},"object is missing after a comma" }
            value,err:=json_node(p)
            if err!=nil { return {},err }
            if _,ae:=append(&array,value); ae!=nil { json.destroy_value(value); return {},"Out of memory" }
            if p.error!=nil { return {},p.error }
            if p.token.kind==.Close_Bracket { json_next(p); if p.error!=nil { return {},p.error }; success=true; return array,nil }
            if p.token.kind==.EOF { return {},"unterminated array" }
            if p.token.kind!=.Comma { return {},"missing value separator" }
            json_next(p)
            if p.error!=nil { return {},p.error }
            if p.token.kind==.Close_Bracket { return {},"object is missing after a comma" }
        }
    case .Invalid: return {},"illegal number"
    case: return {},"illegal value"
    }
}
parse_json :: proc(source: string,allocator:=context.allocator) -> (json.Value,Error) {
    context.allocator=allocator
    p:=JSON_Parser{source=source}
    json_next(&p)
    if p.error!=nil { return {},p.error }
    if p.token.kind==.Invalid { return {},"illegal number" }
    if p.token.kind!=.Open_Brace && p.token.kind!=.Open_Bracket { return {},"illegal value" }
    result,err:=json_node(&p)
    if err!=nil { return {},err }
    if p.token.kind!=.EOF { json.destroy_value(result); return {},"garbage at the end of the document" }
    return result,nil
}
