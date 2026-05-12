DummyInput : Type = (
    .failed: Bool = false
)

read_byte(.self: $&DummyInput) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    result = ..error(.reason = ..stream_read_failed)
}

DummyInput implements Reader

main(.system: System = System()) -> (.status_code: Int32) := {
    stdin :: DummyInput = (
        .failed = false
    )
    result ::= read_line(.allocator = system.allocator, .stdin = $&stdin)

    if is(.value = result, .variant = ..error) {
    } else {
        status_code = 1
        return
    }

    if is(.value = result..error.reason, .variant = ..stream_read_failed) {
    } else {
        status_code = 2
        return
    }

    status_code = 0
}
