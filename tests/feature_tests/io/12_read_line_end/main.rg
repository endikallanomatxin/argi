DummyInput : Type = (
    .done: Bool = false
)

read_byte(.self: $&DummyInput) -> (.result: ReadByte) := {
    result = ..end
}

DummyInput implements Reader

main(.system: System = System()) -> (.status_code: Int32) := {
    stdin :: DummyInput = (
        .done = false
    )
    result ::= read_line(.allocator = system.allocator, .stdin = $&stdin)

    if is(.value = result, .variant = ..end) {
        status_code = 0
        return
    }

    status_code = 1
}
