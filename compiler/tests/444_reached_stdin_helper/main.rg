DummyInput : Type = (
    .read_count: Int32 = 0
)

read_line(.self: $&DummyInput) -> (.line: String) := {
    self& = (
        .read_count = self&.read_count + 1
    )
    line = String(.length = 1)
    bytes_set(.string = $&line, .index = 0, .value = 65)
}

DummyInput implements InputStream#(.line: String)

main() -> (.status_code: Int32) := {
    stdin :: DummyInput = (
        .read_count = 0
    )

    line ::= read_stdin()
    first ::= bytes_get(.string = &line, .index = 0).byte

    if first != 65 {
        status_code = 1
        return
    }

    status_code = stdin.read_count * 10 + 5
}
