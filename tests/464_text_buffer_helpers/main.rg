DummyWriter : Type = (
    .bytes : TextBuffer
)

init(
    .p: $&DummyWriter,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    p&.bytes = TextBuffer(.allocator = allocator, .capacity = 16)
}

deinit(
    .self: $&DummyWriter,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    deinit(.self = $&self&.bytes, .allocator = allocator)
}

write_byte(.self: $&DummyWriter, .byte: UInt8) -> () := {
    push_byte(.self = $&self&.bytes, .byte = byte)
}

flush(.self: $&DummyWriter) -> () := {
}

DummyWriter implements Writer

main(.system: System = System()) -> (.status_code: Int32) := {
    buffer ::= TextBuffer(.allocator = system.allocator, .capacity = 16)
    push_c_string(.self = $&buffer, .text = "OK")

    if buffer.length != 2 {
        status_code = 1
        return
    }

    writer ::= DummyWriter(.allocator = system.allocator)
    write_line_text_buffer(.writer = $&writer, .buffer = &buffer)

    if writer.bytes.length != 3 {
        status_code = 2
        return
    }

    first ::= byte_at(.self = &writer.bytes, .index = 0).byte
    second ::= byte_at(.self = &writer.bytes, .index = 1).byte
    third ::= byte_at(.self = &writer.bytes, .index = 2).byte
    if first != 79 {
        status_code = 3
        return
    }
    if second != 75 {
        status_code = 4
        return
    }
    if third != 10 {
        status_code = 5
        return
    }

    deinit(.self = $&buffer, .allocator = system.allocator)
    deinit(.self = $&writer, .allocator = system.allocator)
    status_code = 0
}
