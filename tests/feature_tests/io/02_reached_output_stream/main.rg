DummyOutput : Type = (
    .flush_count: Int32 = 0
)

flush(.self: $&DummyOutput) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self& = (
        .flush_count = self&.flush_count + 1
    )
    result = ..ok(.value = Void())
}

write(.self: $&DummyOutput, .text: String) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    _ ::= text
    result = ..ok(.value = Void())
}

write_byte(.self: $&DummyOutput, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    _ ::= byte
    result = ..ok(.value = Void())
}

DummyOutput implements Writer

flush_stdout(
    .stdout: $&Writer = #reach stdout, terminal.stdout_writer, system.terminal.stdout_writer,
) -> (.value: Int32) := {
    flush(.self = stdout)
    value = 0
}

main() -> (.status_code: Int32) := {
    system : (
        .terminal: (
            .stdout_writer: DummyOutput
        )
    ) = (
        .terminal = (
            .stdout_writer = (
                .flush_count = 5
            )
        )
    )

    stdout :: DummyOutput = (
        .flush_count = 0
    )

    flush_stdout()
    status_code = stdout.flush_count * 10 + system.terminal.stdout_writer.flush_count
}
