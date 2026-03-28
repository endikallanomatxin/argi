DummyInput : Type = (
    .index: UIntNative = 0
)

read_byte(.self: $&DummyInput) -> (.result: ReadByte) := {
    if self&.index == 0 {
        self& = (.index = 1)
        result = ..ok(.byte = 79)
        return
    }

    if self&.index == 1 {
        self& = (.index = 2)
        result = ..ok(.byte = 75)
        return
    }

    if self&.index == 2 {
        self& = (.index = 3)
        result = ..ok(.byte = 10)
        return
    }

    result = ..end
}

DummyInput implements Reader

main(.system: System = System()) -> (.status_code: Int32) := {
    stdin :: DummyInput = (
        .index = 0
    )
    line ::= read_line(.allocator = system.allocator, .stdin = $&stdin)

    if line.length != 2 {
        status_code = 1
        return
    }

    if bytes_get(.string = &line, .index = 0).byte != 79 {
        status_code = 2
        return
    }

    if bytes_get(.string = &line, .index = 1).byte != 75 {
        status_code = 3
        return
    }

    deinit(.self = $&line, .allocator = system.allocator)
    status_code = 0
}
