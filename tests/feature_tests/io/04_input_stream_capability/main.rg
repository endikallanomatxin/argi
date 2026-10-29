DummyInput := (
    .index : Int32 = 0
)

implement Reader#(DummyInput) (
    .read_byte = (
        .self         : $&DummyInput,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) {
        assume error_tracer

        if self&.index == 0 {
            self&.index = 1
            result = ..ok ..ok 79
            return
        }

        if self&.index == 1 {
            self&.index = 2
            result = ..ok ..ok 75
            return
        }

        result = ..ok ..end
    }
)

main := () -> (.status_code: Int32) {
    stdin_storage :: DummyInput = DummyInput()
    assume reader ::= $&stdin_storage
    first_result ::= Reader#().read_byte(.self = $&stdin_storage)
    second_result ::= Reader#().read_byte(.self = $&stdin_storage)
    third_result ::= Reader#().read_byte(.self = $&stdin_storage)
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
