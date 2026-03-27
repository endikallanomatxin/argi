DummyOutput : Type = (
    .flush_count: Int32 = 0
)

flush(.self: $&DummyOutput) -> () := {
    self& = (
        .flush_count = self&.flush_count + 1
    )
}

write_byte(.self: $&DummyOutput, .byte: UInt8) -> () := {
}

DummyOutput implements Writer

flush_stdout(
    .stdout: $&Writer,
) -> (.value: Int32) := {
    flush(.self = stdout)
    value = 0
}

main() -> (.status_code: Int32) := {
    stdout :: DummyOutput = (
        .flush_count = 0
    )

    flush_stdout(.stdout = $&stdout)
    status_code = stdout.flush_count
}
