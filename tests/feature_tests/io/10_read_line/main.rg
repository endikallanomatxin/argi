DummyInput := (
    .index : UIntNative = 0
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

        if self&.index == 2 {
            self&.index = 3
            result = ..ok ..ok 10
            return
        }

        result = ..ok ..end
    }
)

main := (.system: System) -> (.status_code: Int32) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    stdin_storage :: DummyInput = (
        .index = 0
    )
    assume reader ::= $&stdin_storage
    result ::= read_line(.allocator = $&allocator_storage, .reader = $&stdin_storage)

    if is(.value = result, .variant = ..ok) {
    } else {
        status_code = 1
        return
    }

    outer ::= ~result ..ok
    if is(.value = outer, .variant = ..ok) {
    } else {
        status_code = 2
        return
    }
    line ::= ~outer ..ok

    if byte_length(&line).count != 2 {
        status_code = 3
        return
    }

    if unwrap_or_abort(.value = bytes_get(.view = &line, .index = 0)) != 79 {
        status_code = 4
        return
    }

    if unwrap_or_abort(.value = bytes_get(.view = &line, .index = 1)) != 75 {
        status_code = 5
        return
    }

    deinit(.self = $&line)
    status_code = 0
}
