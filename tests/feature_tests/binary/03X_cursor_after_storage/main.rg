main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    bytes ::= DynamicArray#(.t: UInt8)(.capacity = 2)!
    push(.self = $&bytes, .value = 1)!
    push(.self = $&bytes, .value = 2)!
    reader ::= ByteReader(.bytes = array_view_ro(.array = &bytes).view)
    deinit(.self = $&bytes)
    _ ::= read_uint16(.self = $&reader, .order = ..big)!
}
