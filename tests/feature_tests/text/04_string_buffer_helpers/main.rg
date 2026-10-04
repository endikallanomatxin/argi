DummyWriter: Type = (
    .bytes : String
)

DummyWriter init(
        .allocator : $&Allocator,
    ) -> (
        .result : DummyWriter
    ) := {
    assume allocator

    result.bytes = unwrap_or_abort(.value = String(.allocator = allocator, .capacity = 16))
}

DummyWriter deinit(
        .self      : $&DummyWriter,
        .allocator : $&Allocator,
    ) -> () := {
    assume allocator

    deinit(.self = $&self&.bytes, .allocator = allocator)
}

write_byte(
        .self      : $&DummyWriter,
        .byte      : UInt8,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    assume allocator

    pushed ::= push_byte(.self = $&self&.bytes, .byte = byte, .allocator = allocator)
    if is(.value = pushed, .variant = ..error) {
        result = ..error(.reason = ..stream_write_failed)
        return
    }
    result = ..ok(.value = Void())
}

flush(
        .self : $&DummyWriter
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    result = ..ok(.value = Void())
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    buffer ::= unwrap_or_abort(.value = String(.allocator = $&allocator_storage, .capacity = 16))
    match push_c_string(.self = $&buffer, .text = "OK") {
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

    writer ::= DummyWriter(.allocator = $&allocator_storage)
    i :: UIntNative = 0
    while i < buffer.length {
        write_byte(
            .self      = $&writer
            .byte      = bytes_get(.string = &buffer, .index = i).byte
            .allocator = $&allocator_storage
        )
        i = i + 1
    }
    write_byte(.self = $&writer, .byte = 10, .allocator = $&allocator_storage)

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

    deinit(.self = $&buffer, .allocator = $&allocator_storage)
    deinit(.self = $&writer, .allocator = $&allocator_storage)
    status_code = 0
}
