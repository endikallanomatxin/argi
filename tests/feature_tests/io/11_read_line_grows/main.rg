DummyInput : Type = (
    .index: UIntNative = 0
)

read_byte(.self: $&DummyInput) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    if self&.index < 20 {
        current ::= self&.index
        self& = (.index = current + 1)
        result = ..ok ..ok 65
        return
    }

    if self&.index == 20 {
        self& = (.index = 21)
        result = ..ok ..ok 10
        return
    }

    result = ..ok ..end
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

    line ::= result..ok..ok

    if line.length != 20 {
        status_code = 2
        return
    }

    if capacity(.self = &line).value < 20 {
        status_code = 3
        return
    }

    if bytes_get(.string = &line, .index = 0).byte != 65 {
        status_code = 4
        return
    }

    if bytes_get(.string = &line, .index = 19).byte != 65 {
        status_code = 5
        return
    }

    deinit(.self = $$&line, .allocator = system.allocator)
    status_code = 0
}
