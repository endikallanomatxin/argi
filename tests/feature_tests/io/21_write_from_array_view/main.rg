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
    allocator_storage :: CAllocator = CAllocator()
    assume allocator ::= $&allocator_storage
    allocated ::= allocate(.self = $&allocator_storage, .size = 3)
    match allocated {
    ..error _ { status_code = 10 }
    ..ok ~ allocation {

    buffer ::= array_view#(.t: UInt8)(
        .data = allocation.data,
        .length = 3,
    )
    buffer[0] = 2
    buffer[1] = 3
    buffer[2] = 5

    stdout_storage :: DummyOutput = (

        .write_count = 0,
    )
    assume stdout ::= $&stdout_storage
    write_result ::= write(.self = $&stdout_storage, .buffer = buffer)

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

    if stdout_storage.write_count != 3 {
        status_code = 13
        return
    }

    status_code = 0
    }
    }
}
