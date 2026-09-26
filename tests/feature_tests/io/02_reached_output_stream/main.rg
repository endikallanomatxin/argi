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
    .stdout: $&Writer = reach stdout, terminal.stdout, system.terminal.stdout,
) -> (.value: Int32) := {
    assume stdout

    flush(.self = stdout)
    value = 0
}

main() -> (.status_code: Int32) := {
    system : (
        .terminal: (
            .stdout: DummyOutput
        )
    ) = (
        .terminal = (
            .stdout = (
                .flush_count = 5
            )
        )
    )

    stdout_storage :: DummyOutput = (

        .flush_count = 0
    )
    assume stdout ::= $&stdout_storage

    flush_stdout()
    status_code = stdout_storage.flush_count * 10 + system.terminal.stdout.flush_count
}
