DummyOutput := (
    .write_count : Int32 = 0,
    .flush_count : Int32 = 0
)

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

main := (.system: System) -> (.status_code: Int32 = 0) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    stdout_storage :: DummyOutput = DummyOutput()
    assume writer ::= $&stdout_storage
    stderr_storage :: DummyOutput = DummyOutput()

    text ::= unwrap_or_abort(.value = String(.length = 1))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 65))
    view ::= view(.self = &text)

    print(view)
    flush()
    {
        assume writer ::= $&stderr_storage
        print_error(view)
        flush_error()
    }

    if stdout_storage.write_count != 2 {
        status_code = 1
        return
    }

    if stdout_storage.flush_count != 1 {
        status_code = 2
        return
    }

    if stderr_storage.write_count != 1 {
        status_code = 3
        return
    }

    if stderr_storage.flush_count != 1 {
        status_code = 4
        return
    }

    stdin_storage :: DummyInput = (

        .index = 0
    )
    assume reader ::= $&stdin_storage
    buffer ::= unwrap_or_abort(
        .value = string_with_capacity(.allocator = $&allocator_storage, .capacity = 4)
    )
    into_buffer ::= read_line_into_buffer($&buffer)
    if is(.value = into_buffer, .variant = ..ok) {
    } else {
        status_code = 5
        return
    }

    if byte_length(&buffer).count != 2 {
        status_code = 6
        return
    }

    if unwrap_or_abort(.value = bytes_get(.view = &buffer, .index = 0)) != 79 {
        status_code = 7
        return
    }

    if unwrap_or_abort(.value = bytes_get(.view = &buffer, .index = 1)) != 75 {
        status_code = 8
        return
    }

    deinit(.self = $&buffer)

    stdin_storage = (
        .index = 0
    )
    line_result ::= read_line()
    match line_result {
        ..error _ {
            status_code = 9
            return
        }
        ..ok ~outer {
            match outer {
                ..end {
                    status_code = 9
                    return
                }
                ..ok ~line_payload {
                    line ::= ~line_payload
                    if byte_length(&line).count != 2 {
                        status_code = 10
                        return
                    }

                    if unwrap_or_abort(.value = bytes_get(.view = &line, .index = 0)) != 79 {
                        status_code = 11
                        return
                    }

                    if unwrap_or_abort(.value = bytes_get(.view = &line, .index = 1)) != 75 {
                        status_code = 12
                        return
                    }

                    deinit(.self = $&line)
                }
            }
        }
    }
    deinit(.self = $&text)
}

implement Writer#(DummyOutput) (
    .write_byte = (
        .self         : $&DummyOutput,
        .byte         : UInt8,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        _ ::= byte
        self&.write_count = self&.write_count + 1
        result = ..ok(.value = Void())
    }

    .flush = (
        .self         : $&DummyOutput,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        self&.flush_count = self&.flush_count + 1
        result = ..ok(.value = Void())
    }
)
