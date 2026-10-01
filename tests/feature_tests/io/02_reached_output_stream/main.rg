DummyOutput : Type = (
    .flush_count: Int32 = 0
)

flush(.self: $&DummyOutput) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self& = (
        .flush_count = self&.flush_count + 1
    )
    result = ..ok(.value = Void())
}

write(.self: $&DummyOutput, .text: &String) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    _ ::= text
    result = ..ok(.value = Void())
}

write_byte(.self: $&DummyOutput, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    _ ::= byte
    result = ..ok(.value = Void())
}

DummyOutput implements Writer

flush_stdout(
    .writer: $&Writer = reach writer, terminal.writer, system.terminal.writer,
) -> (.value: Int32) := {
    assume writer

    flush(.self = writer)
    value = 0
}

main() -> (.status_code: Int32) := {
    system : (
        .terminal: (
            .writer: DummyOutput
        )
    ) = (
        .terminal = (
            .writer = (
                .flush_count = 5
            )
        )
    )

    stdout_storage :: DummyOutput = (

        .flush_count = 0
    )
    assume writer ::= $&stdout_storage

    flush_stdout()
    status_code = stdout_storage.flush_count * 10 + system.terminal.writer.flush_count
}
