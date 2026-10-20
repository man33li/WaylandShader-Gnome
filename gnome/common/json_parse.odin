package common

import json "core:encoding/json"
import "core:math"
import "core:strconv"
import "core:unicode/utf8"

JSON_Parser :: struct { tokenizer: json.Tokenizer, token: json.Token, error: Error, depth: int }
json_next :: proc(p: ^JSON_Parser) {
    if p.error!=nil { return }
    for p.tokenizer.r==' ' || p.tokenizer.r=='\t' || p.tokenizer.r=='\n' || p.tokenizer.r=='\r' { json.next_rune(&p.tokenizer) }
    if p.tokenizer.r=='\v' || p.tokenizer.r=='\f' || p.tokenizer.r==0 { p.token={kind=.Invalid}; return }
    token,err:=json.get_token(&p.tokenizer)
    p.token=token
    #partial switch err {
    case .None,.EOF:
    case .String_Not_Terminated: p.error="unterminated string"
    case .Invalid_String:
        if len(token.text)<2 || token.text[len(token.text)-1]!='"' { p.error="unterminated string" }
    case .Invalid_Rune: p.error="invalid UTF8 string"
    case .Invalid_Number: p.error="illegal number"
    case: p.error="illegal value"
    }
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
        if c!='\\' { bytes[count]=c; count+=1; continue }
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
            code,ok:=strconv.parse_u64(source[i+1:i+5],16)
            if !ok { return "","invalid escape sequence" }
            i+=4
            if code>=0xd800 && code<=0xdbff && i+6<len(source) && source[i+1:i+3]=="\\u" {
                low,valid:=strconv.parse_u64(source[i+3:i+7],16)
                if valid && low>=0xdc00 && low<=0xdfff { code=0x10000+((code-0xd800)<<10)+(low-0xdc00); i+=6 }
            }
            encoded,width:=utf8.encode_rune(rune(code))
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
            value,err:=json_node(p)
            if err!=nil { return {},err }
            if _,ae:=append(&array,value); ae!=nil { json.destroy_value(value); return {},"Out of memory" }
            if p.error!=nil { return {},p.error }
            if p.token.kind==.Close_Bracket { json_next(p); if p.error!=nil { return {},p.error }; success=true; return array,nil }
            if p.token.kind==.EOF { return {},"unterminated array" }
            if p.token.kind!=.Comma { return {},"missing value separator" }
            json_next(p)
            if p.error!=nil { return {},p.error }
            if p.token.kind==.Close_Bracket { return {},"illegal value" }
        }
    case .Invalid: return {},"illegal number"
    case: return {},"illegal value"
    }
}
parse_json :: proc(source: string,allocator:=context.allocator) -> (json.Value,Error) {
    context.allocator=allocator
    p:=JSON_Parser{tokenizer=json.make_tokenizer(source,spec=.JSON,parse_integers=false)}
    json_next(&p)
    if p.error!=nil { return {},p.error }
    if p.token.kind==.Invalid { return {},"illegal number" }
    if p.token.kind!=.Open_Brace && p.token.kind!=.Open_Bracket { return {},"illegal value" }
    result,err:=json_node(&p)
    if err!=nil { return {},err }
    if p.token.kind!=.EOF { json.destroy_value(result); return {},"garbage at the end of the document" }
    return result,nil
}
