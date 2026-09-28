DummyInput : Type = (
    .failed: Bool = false
)

read_byte(.self: $&DummyInput) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    result = ..error(.reason = ..stream_read_failed)
}

DummyInput implements Reader

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    stdin_storage :: DummyInput = (
        .failed = false
    )
    assume stdin ::= $&stdin_storage
    result ::= read_line(.allocator = $&allocator_storage, .stdin = $&stdin_storage)

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
