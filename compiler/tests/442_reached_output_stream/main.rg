DummyOutput : Type = (
    .flush_count: Int32 = 0
)

flush(.self: $&DummyOutput) -> () := {
    self& = (
        .flush_count = self&.flush_count + 1
    )
}

write(.self: $&DummyOutput, .text: String) -> () := {
}

DummyOutput implements OutputStream#(.text: String)

flush_stdout(
    .stdout: $&OutputStream#(.text: String) = #reach stdout, terminal.stdout, system.terminal.stdout,
) -> (.value: Int32) := {
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

    stdout :: DummyOutput = (
        .flush_count = 0
    )

    flush_stdout()
    status_code = stdout.flush_count * 10 + system.terminal.stdout.flush_count
}
