DummyOutput : Type = (
    .flush_count: Int32 = 0
)

flush(.self: $&DummyOutput) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self& = (
        .flush_count = self&.flush_count + 1
    )
    result = ..ok(.value = Void())
}

write_byte(.self: $&DummyOutput, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    _ ::= byte
    result = ..ok(.value = Void())
}

DummyOutput implements Writer

flush_stdout(
    .writer: $&Writer,
) -> (.value: Int32) := {
    assume writer

    flush(.self = writer)
    value = 0
}

main() -> (.status_code: Int32) := {
    stdout_storage :: DummyOutput = (
        .flush_count = 0
    )
    assume writer ::= $&stdout_storage

    flush_stdout(.writer = $&stdout_storage)
    status_code = stdout_storage.flush_count
}
