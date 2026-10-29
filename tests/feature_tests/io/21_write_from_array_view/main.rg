DummyOutput := (
    .write_count : UIntNative = 0
)

main := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.status_code: Int32) {
    assume error_tracer
    bytes: Array#(.n = 3, .t: UInt8) = (0, 0, 0)
    buffer ::= view(.self = $&bytes)
    first_set ::= set#(.t: UInt8)(.self = $&buffer, .index = 0, .value = 2).result
    second_set ::= set#(.t: UInt8)(.self = $&buffer, .index = 1, .value = 3).result
    third_set ::= set#(.t: UInt8)(.self = $&buffer, .index = 2, .value = 5).result
    if [
        is(.value = first_set, .variant = ..error)
        or is(.value = second_set, .variant = ..error)
        or is(.value = third_set, .variant = ..error)
    ] {
        status_code = 14
        return
    }

    stdout_storage :: DummyOutput = (

        .write_count = 0
    )
    assume writer ::= $&stdout_storage
    write_result ::= write(.self = $&stdout_storage, .value = buffer)

    if is(.value = write_result, .variant = ..ok) {
    } else {
        status_code = 11
        return
    }

    wrote ::= write_result ..ok
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

implement Writer#(DummyOutput) (
    .write_byte = (.self: $&DummyOutput, .byte: UInt8, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume error_tracer

        self&.write_count = self&.write_count + 1
        result = ..ok Void()
    }

    .flush = (.self: $&DummyOutput, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume error_tracer

        result = ..ok Void()
    }
)
