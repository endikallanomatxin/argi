DummyOutput : Type = (
    .write_count: Int32 = 0
    .flush_count: Int32 = 0
)

write_byte(.self: $&DummyOutput, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self& = (
        .write_count = self&.write_count + 1,
        .flush_count = self&.flush_count,
    )
    result = ..ok(.value = Void())
}

flush(.self: $&DummyOutput) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self& = (
        .write_count = self&.write_count,
        .flush_count = self&.flush_count + 1,
    )
    result = ..ok(.value = Void())
}

DummyOutput implements Writer

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    stderr_storage :: DummyOutput = (
        .write_count = 0,
        .flush_count = 0,
    )
    assume stderr ::= $&stderr_storage
    text ::= String(.length = 1)
    bytes_set(.string = $&text, .index = 0, .value = 69)
    view ::= as_view(.self = &text)

    print_error(.stderr = $&stderr_storage, .value = view)
    flush_error(.stderr = $&stderr_storage)

    status_code = stderr_storage.write_count * 10 + stderr_storage.flush_count
}
