package glib

// Deterministic, single-threaded test doubles. No native pointers reach real FFI.
GType :: uintptr
Error :: struct { domain: u32, code: i32, message: cstring }
Object :: struct { refs, id, kind: int, ctx: rawptr, held: ^Object }
objects: [256]Object
count: int
error_frees: int
make :: proc(kind: int, ctx: rawptr = nil) -> ^Object {
    assert(count < len(objects))
    p := &objects[count]
    p^ = {refs=1, id=count, kind=kind, ctx=ctx}
    count += 1
    return p
}
reset :: proc() {
    for i in 0..<count { assert(objects[i].refs == 0, "mock object leak") }
    objects = {}; count = 0; error_frees = 0
}
live_refs :: proc() -> int {
    n := 0
    for i in 0..<count { n += objects[i].refs }
    return n
}
g_object_ref :: proc(p: rawptr) -> rawptr {
    o := cast(^Object)p
    assert(o != nil && o.refs > 0, "ref of invalid mock object")
    o.refs += 1
    return p
}
g_object_unref :: proc(p: rawptr) {
    o := cast(^Object)p
    assert(o != nil && o.refs > 0, "double unref/invalid mock object")
    o.refs -= 1
    if o.refs == 0 && o.held != nil { g_object_unref(o.held); o.held = nil }
}
g_object_get :: proc(p: rawptr, name: cstring, value: ^rawptr, end: rawptr) {
    assert(string(name) == "context" && end == nil)
    value^ = g_object_ref((cast(^Object)p).ctx)
}
g_type_check_instance_is_a :: proc(p: rawptr, kind: GType) -> bool {
    assert(p != nil)
    return (cast(^Object)p).kind == int(kind)
}
g_error_free :: proc(err: ^Error) { assert(err != nil); error_frees += 1 }
