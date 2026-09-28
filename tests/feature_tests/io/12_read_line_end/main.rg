DummyInput : Type = (
    .done: Bool = false
)

read_byte(.self: $&DummyInput) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    result = ..ok ..end
}

DummyInput implements Reader

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    stdin_storage :: DummyInput = (
        .done = false
    )
    assume stdin ::= $&stdin_storage
    result ::= read_line(.allocator = $&allocator_storage, .stdin = $&stdin_storage)

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
                    deinit(.self = $&line, .allocator = $&allocator_storage)
                    status_code = 1
                }
            }
        }
    }
}
