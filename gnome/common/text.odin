package common

import "core:unicode/utf8"

// JSON strings use WTF-8 internally so isolated UTF-16 surrogates survive export.
text_decode :: proc(source: string, index: int) -> (rune, int) {
    s:=source[index:]
    if len(s)>=3 && s[0]==0xed && s[1]>=0xa0 && s[1]<=0xbf && s[2]>=0x80 && s[2]<=0xbf {
        return rune((u32(s[0]&15)<<12)|(u32(s[1]&63)<<6)|u32(s[2]&63)),3
    }
    return utf8.decode_rune(s)
}
text_encode :: proc(code: rune) -> ([4]u8,int) {
    if code>=0xd800 && code<=0xdfff {
        return [4]u8{0xed,u8(0x80|((u32(code)>>6)&63)),u8(0x80|(u32(code)&63)),0},3
    }
    return utf8.encode_rune(code)
}
// Filesystem bytes and C/GTK strings use replacement UTF-8, never internal WTF-8.
text_utf8 :: proc(source: string,allocator:=context.allocator,internal: bool=true) -> (string,Error) {
    context.allocator=allocator
    bytes,err:=make([dynamic]u8,0,len(source))
    if err!=nil { return "","Out of memory" }
    for i:=0; i<len(source); {
        code,width:=text_decode(source,i)
        if !internal { code,width=utf8.decode_rune(source[i:]) }
        if code>=0xd800 && code<=0xdfff { code=0xfffd }
        encoded,count:=utf8.encode_rune(code)
        if _,ae:=append(&bytes,..encoded[:count]); ae!=nil { delete(bytes); return "","Out of memory" }
        i+=width
    }
    return string(bytes[:]),nil
}
