DummyInput : Type = (
    .read_count: Int32 = 0
)

read_line(.self: $&DummyInput) -> (.line: String) := {
    self& = (
        .read_count = self&.read_count + 1
    )
    line = String(.length = 1)
    bytes_set(.string = $&line, .index = 0, .value = 66)
}

DummyInput implements InputStream#(.line: String)

DummyOutput : Type = (
    .unused: Int32 = 0
)

write(.self: $&DummyOutput, .text: String) -> () := {
}

flush(.self: $&DummyOutput) -> () := {
}

DummyOutput implements OutputStream#(.text: String)

main() -> (.status_code: Int32) := {
    stdin_impl :: DummyInput = (
        .read_count = 0
    )
    stdout_impl :: DummyOutput = (
        .unused = 0
    )
    stderr_impl :: DummyOutput = (
        .unused = 0
    )

    terminal :: Terminal#(
        .stdin_stream = DummyInput,
        .stdout_stream = DummyOutput,
        .stderr_stream = DummyOutput,
    ) = (
        .stdin = $&stdin_impl,
        .stdout = $&stdout_impl,
        .stderr = $&stderr_impl,
    )

    line ::= read_stdin()
    first ::= bytes_get(.string = &line, .index = 0).byte

    if first != 66 {
        status_code = 1
        return
    }

    status_code = stdin_impl.read_count * 10 + 6
}
