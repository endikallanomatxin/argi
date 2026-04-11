DummyInput : Type = (
    .index: Int32 = 0
)

read_byte(
    .self: $&DummyInput,
 ) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    if self&.index == 0 {
        self& = (
            .index = 1
        )
        result = ..ok ..ok 79
        return
    }

    if self&.index == 1 {
        self& = (
            .index = 2
        )
        result = ..ok ..ok 75
        return
    }

    result = ..ok ..end
}

DummyInput implements Reader

main() -> (.status_code: Int32) := {
    stdin :: DummyInput = DummyInput()
    first_result ::= read_byte(.self = $&stdin)
    second_result ::= read_byte(.self = $&stdin)
    third_result ::= read_byte(.self = $&stdin)

    if is(.value = first_result, .variant = ..ok) {
    } else {
        status_code = 1
        return
    }

    if is(.value = second_result, .variant = ..ok) {
    } else {
        status_code = 2
        return
    }

    if is(.value = third_result..ok, .variant = ..end) {
    } else {
        status_code = 3
        return
    }

    first ::= first_result..ok..ok
    second ::= second_result..ok..ok

    if first != 79 {
        status_code = 4
        return
    }

    if second != 75 {
        status_code = 5
        return
    }

    status_code = 0
}
