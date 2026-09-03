DummyInput : Type = (
    .index: Int32 = 0
)

read_byte(
    .self: $&DummyInput,
) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    if self&.index == 0 {
        self& = (.index = 1)
        result = ..ok ..ok 65
        return
    }

    if self&.index == 1 {
        self& = (.index = 2)
        result = ..ok ..ok 66
        return
    }

    result = ..ok ..end
}

DummyInput implements Reader

main() -> (.status_code: Int32) := {
    allocator :: CAllocator = CAllocator()
    allocated ::= allocate(.self = $&allocator, .size = 4)
    match allocated {
    ..error _ { status_code = 10 }
    ..ok ~ allocation {

    buffer ::= array_view#(.t: UInt8)(
        .data = allocation.data,
        .length = 4,
    )
    stdin :: DummyInput = DummyInput()
    read_result ::= read(.self = $&stdin, .buffer = buffer)

    if is(.value = read_result, .variant = ..ok) {
    } else {
        status_code = 11
        return
    }

    copied ::= read_result..ok
    if copied != 2 {
        status_code = 12
        return
    }

    if buffer[0] != 65 {
        status_code = 13
        return
    }

    if buffer[1] != 66 {
        status_code = 14
        return
    }

    status_code = 0
    }
    }
}
