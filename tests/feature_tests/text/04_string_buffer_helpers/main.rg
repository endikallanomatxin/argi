DummyWriter := (
    .bytes : String
)

DummyWriterInitArgs: Type = (
    .allocator : Virtual#(Allocator)
)

implement Init#(
    DummyWriter, DummyWriterInitArgs
) (
    .Result : Type = DummyWriter

    .init = DummyWriterInitArgs -> (.result: Result) {

        _init_allocator ::= ~allocator

        assume allocator := _init_allocator

        result.bytes = unwrap_or_abort(
            .value = string_with_capacity(.allocator = _init_allocator, .capacity = 16)
        )
    }
)

implement Deinit#(DummyWriter) (
    .deinit = (.self: $&DummyWriter) -> () {
        deinit(.self = $&self&.bytes)
    }
)

append_test_byte := (
    .self: $&DummyWriter, .byte: UInt8, .allocator: Virtual#(Allocator)
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {

    assume allocator

    pushed ::= push_ascii(.self = $&self&.bytes, .byte = byte, .allocator = allocator)
    if is(.value = pushed, .variant = ..error) {
        result = ..error(.reason = ..stream_write_failed)
        return
    }
    result = ..ok(.value = Void())
}

main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    buffer ::= unwrap_or_abort(
        .value = string_with_capacity(.allocator = allocator, .capacity = 16)
    )
    match push_c_string(.self = $&buffer, .text = "OK") {
        ..ok _ {
        }
        ..error _ {
            status_code = 10
            return
        }
    }

    if byte_length(&buffer).count != 2 {
        status_code = 1
        return
    }

    writer ::= DummyWriter(.allocator = allocator)
    i :: UIntNative = 0
    while i < byte_length(&buffer).count {
        append_test_byte(
            .self      = $&writer
            .byte      = unwrap_or_abort(.value = bytes_get(.view = &buffer, .index = i))
            .allocator = allocator
        )
        i = i + 1
    }
    append_test_byte(.self = $&writer, .byte = 10, .allocator = allocator)

    if byte_length(&writer.bytes).count != 3 {
        status_code = 2
        return
    }

    first ::= unwrap_or_abort(.value = bytes_get(.view = &writer.bytes, .index = 0))
    second ::= unwrap_or_abort(.value = bytes_get(.view = &writer.bytes, .index = 1))
    third ::= unwrap_or_abort(.value = bytes_get(.view = &writer.bytes, .index = 2))
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

    deinit(.self = $&buffer)
    deinit(.self = $&writer)
    status_code = 0
}
