DummyOutput : Type = (
    .flush_count: Int32 = 0
)

flush(.self: $&DummyOutput) -> (.result: Errable#(.t: Bool, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self& = (
        .flush_count = self&.flush_count + 1
    )
    result = ..ok(.value = true)
}

write(.self: $&DummyOutput, .text: String) -> (.result: Errable#(.t: Bool, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    _ ::= text
    result = ..ok(.value = true)
}

write_byte(.self: $&DummyOutput, .byte: UInt8) -> (.result: Errable#(.t: Bool, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    _ ::= byte
    result = ..ok(.value = true)
}

DummyOutput implements Writer

flush_stdout(
    .stdout: $&Writer = #reach stdout, terminal.stdout_buffered_writer, system.terminal.stdout_buffered_writer,
) -> (.value: Int32) := {
    flush(.self = stdout)
    value = 0
}

main() -> (.status_code: Int32) := {
    system : (
        .terminal: (
            .stdout_buffered_writer: DummyOutput
        )
    ) = (
        .terminal = (
            .stdout_buffered_writer = (
                .flush_count = 5
            )
        )
    )

    stdout :: DummyOutput = (
        .flush_count = 0
    )

    flush_stdout()
    status_code = stdout.flush_count * 10 + system.terminal.stdout_buffered_writer.flush_count
}
