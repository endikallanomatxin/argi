DummyWriter : Type = (
    .flush_count: Int32 = 0
)

write_byte(.self: $&DummyWriter, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self&
    byte
    result = ..ok(.value = Void())
}

flush(.self: $&DummyWriter) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self& = (
        .flush_count = self&.flush_count + 1
    )
    result = ..ok(.value = Void())
}

DummyWriter implements Writer

Wrapper : Type = (
    .base: $&DummyWriter
)

write_byte(
    .self: $&Wrapper,
    .byte: UInt8,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    write_byte(.self = self&.base, .byte = byte)
    result = ..ok(.value = Void())
}

flush(
    .self: $&Wrapper,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    flush(.self = self&.base)
    result = ..ok(.value = Void())
}

Wrapper implements Writer

accept(
    .writer: $&Writer,
) -> (.status_code: Int32) := {
    flush(.self = writer)
    status_code = 0
}

main() -> (.status_code: Int32) := {
    base :: DummyWriter = (
        .flush_count = 0
    )
    wrapper :: Wrapper = (
        .base = $&base
    )

    _ ::= accept(.writer = $&wrapper)
    status_code = 0
}
