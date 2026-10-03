DummyWriter : Type = (
    .flush_count: Int32 = 0
)

write_byte(.self: $&DummyWriter, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    _ ::= byte
    result = ..ok(.value = Void())
}

flush(.self: $&DummyWriter) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self& = (
        .flush_count = self&.flush_count + 1
    )
    result = ..ok(.value = Void())
}

DummyWriter implements Writer

Holder : Type = (
    .writer: $&Writer
)

Holder init(.writer: $&DummyWriter,
) -> (.result: Holder) := {
    result.writer = writer
}

main() -> (.status_code: Int32) := {
    writer :: DummyWriter = (
        .flush_count = 0
    )
    holder :: Holder

    holder = Holder(.writer = $&writer)

    writer_address :: UIntNative = UIntNative(.value = $&writer)
    stored_address :: UIntNative = UIntNative(.value = holder.writer)
    if writer_address == stored_address {
        status_code = 0
    } else {
        status_code = 1
    }
}
