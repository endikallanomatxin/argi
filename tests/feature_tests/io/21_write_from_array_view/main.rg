DummyOutput : Type = (
    .write_count : UIntNative = 0
)

write_byte(
    .self: $&DummyOutput,
    .byte: UInt8,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self& = (
        .write_count = self&.write_count + 1,
    )
    result = ..ok Void()
}

flush(
    .self: $&DummyOutput,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = ..ok Void()
}

DummyOutput implements Writer

main() -> (.status_code: Int32) := {
    allocator :: CAllocator = CAllocator()
    allocation ::= allocate_owned(.self = $&allocator, .size = 3)

    buffer ::= array_view#(.t: UInt8)(
        .data = allocation.data,
        .length = 3,
    )
    buffer[0] = 2
    buffer[1] = 3
    buffer[2] = 5

    stdout :: DummyOutput = (
        .write_count = 0,
    )
    write_result ::= write(.self = $&stdout, .buffer = buffer)

    if is(.value = write_result, .variant = ..ok) {
    } else {
        status_code = 11
        return
    }

    wrote ::= write_result..ok
    if wrote != 3 {
        status_code = 12
        return
    }

    if stdout.write_count != 3 {
        status_code = 13
        return
    }

    status_code = 0
}
