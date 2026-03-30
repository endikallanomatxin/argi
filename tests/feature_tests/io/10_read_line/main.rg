DummyInput : Type = (
    .index: UIntNative = 0
)

read_byte(.self: $&DummyInput) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    if self&.index == 0 {
        self& = (.index = 1)
        result = ..ok(.value = ..ok(.byte = 79))
        return
    }

    if self&.index == 1 {
        self& = (.index = 2)
        result = ..ok(.value = ..ok(.byte = 75))
        return
    }

    if self&.index == 2 {
        self& = (.index = 3)
        result = ..ok(.value = ..ok(.byte = 10))
        return
    }

    result = ..ok(.value = ..end)
}

DummyInput implements Reader

main(.system: System = System()) -> (.status_code: Int32) := {
    stdin :: DummyInput = (
        .index = 0
    )
    result ::= read_line(.allocator = system.allocator, .stdin = $&stdin)

    if is(.value = result, .variant = ..ok) {
    } else {
        status_code = 1
        return
    }

    line ::= result..ok.value..ok.text

    if line.length != 2 {
        status_code = 2
        return
    }

    if bytes_get(.string = &line, .index = 0).byte != 79 {
        status_code = 3
        return
    }

    if bytes_get(.string = &line, .index = 1).byte != 75 {
        status_code = 4
        return
    }

    deinit(.self = $&line, .allocator = system.allocator)
    status_code = 0
}
