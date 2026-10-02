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
    bytes : Array#(.n = 4, .t: UInt8) = (0, 0, 0, 0)
    buffer ::= array_view(.array = $&bytes)
    stdin_storage :: DummyInput = DummyInput()
    assume reader ::= $&stdin_storage
    read_result ::= read(.self = $&stdin_storage, .buffer = buffer)

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

    first_result ::= get(.self = &buffer, .index = 0).result
    if is(.value = first_result, .variant = ..error) {
        status_code = 13
        return
    }
    if first_result..ok != 65 {
        status_code = 13
        return
    }

    second_result ::= get(.self = &buffer, .index = 1).result
    if is(.value = second_result, .variant = ..error) {
        status_code = 14
        return
    }
    if second_result..ok != 66 {
        status_code = 14
        return
    }

    status_code = 0
}
