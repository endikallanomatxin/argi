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
    first :: UInt8 = 0
    second :: UInt8 = 0

    match first_result {
        ..ok first_read {
            match first_read {
                ..ok value { first = value }
                ..end {
                    status_code = 1
                    return
                }
            }
        }
        ..error _ {
            status_code = 1
            return
        }
    }

    match second_result {
        ..ok second_read {
            match second_read {
                ..ok value { second = value }
                ..end {
                    status_code = 2
                    return
                }
            }
        }
        ..error _ {
            status_code = 2
            return
        }
    }

    match third_result {
        ..ok third_read {
            match third_read {
                ..ok _ {
                    status_code = 3
                    return
                }
                ..end {}
            }
        }
        ..error _ {
            status_code = 3
            return
        }
    }

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
