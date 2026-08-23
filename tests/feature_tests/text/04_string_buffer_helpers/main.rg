DummyWriter : Type = (
    .bytes : String
)

init(
    .p: $&DummyWriter,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () #trusted_temporal := {
    p&.bytes = String(.allocator = allocator, .capacity = 16)
}

deinit(
    .self: $$&DummyWriter,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    deinit(.self = $$&self&.bytes, .allocator = allocator)
}

write_byte(.self: $&DummyWriter, .byte: UInt8, .allocator: $&Allocator) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    _ ::= allocator
    string_append_byte(.self = $&self&.bytes, .byte = byte)
    result = ..ok(.value = Void())
}

flush(.self: $&DummyWriter) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = ..ok(.value = Void())
}

main(.system: System = System()) -> (.status_code: Int32) := {
    buffer ::= String(.allocator = system.allocator, .capacity = 16)
    match push_c_string(.self = $$&buffer, .text = "OK") {
        ..ok _ {
        }
        ..error _ {
            status_code = 10
            return
        }
    }

    if buffer.length != 2 {
        status_code = 1
        return
    }

    writer ::= DummyWriter(.allocator = system.allocator)
    i :: UIntNative = 0
    while i < buffer.length {
        write_byte(.self = $&writer, .byte = bytes_get(.string = &buffer, .index = i).byte, .allocator = system.allocator)
        i = i + 1
    }
    write_byte(.self = $&writer, .byte = 10, .allocator = system.allocator)

    if writer.bytes.length != 3 {
        status_code = 2
        return
    }

    first ::= bytes_get(.string = &writer.bytes, .index = 0).byte
    second ::= bytes_get(.string = &writer.bytes, .index = 1).byte
    third ::= bytes_get(.string = &writer.bytes, .index = 2).byte
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

    deinit(.self = $$&buffer, .allocator = system.allocator)
    deinit(.self = $$&writer, .allocator = system.allocator)
    status_code = 0
}
