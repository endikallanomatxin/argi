DummyInput : Type = (
    .done: Bool = false
)

read_byte(.self: $&DummyInput) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    result = ..ok ..end
}

DummyInput implements Reader

main(.system: System = System()) -> (.status_code: Int32) := {
    stdin :: DummyInput = (
        .done = false
    )
    result ::= read_line(.allocator = system.allocator, .stdin = $&stdin)

    match result {
        ..error _ {
            status_code = 1
        }
        ..ok ~ line_result {
            match line_result {
                ..end {
                    status_code = 0
                }
                ..ok ~ line_payload {
                    line ::= ~line_payload
                    deinit(.self = $&line, .allocator = system.allocator)
                    status_code = 1
                }
            }
        }
    }
}
