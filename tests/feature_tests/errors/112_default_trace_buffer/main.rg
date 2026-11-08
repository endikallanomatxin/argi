main := () -> (.status_code: Int32 = 0) {
    first ::= FixedSizeErrorTracer()
    second ::= FixedSizeErrorTracer()
    first_handle ::= Virtual#(ErrorTracer)($&first)
    second_handle ::= Virtual#(ErrorTracer)($&second)
    ErrorTracer#(
    ).add_context(.self = $&first_handle, .location = error_location_id(), .context = "first")
    ErrorTracer#(
    ).add_context(.self = $&second_handle, .location = error_location_id(), .context = "second")
    output ::= Output(.expected = "first")
    output_handle ::= Virtual#(Writer)($&output)
    ErrorTracer#().report(.self = $&first_handle, .writer = $&output_handle) handle ignored, recovered {
        abort
    }
    if output.found == false { abort }
    output_two ::= Output(.expected = "second")
    output_two_handle ::= Virtual#(Writer)($&output_two)
    ErrorTracer#().report(.self = $&second_handle, .writer = $&output_two_handle) handle ignored, recovered {
        abort
    }
    if output_two.found == false { abort }
}

Output := (.expected: StringView, .index: UIntNative = 0, .found: Bool = false)

implement Writer#(Output) (
    .write_byte = (.self: $&Output, .byte: UInt8) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()
    ) {
        expected ::= bytes_get(&self&.expected, self&.index) handle ignored, recovered {
            abort
        }
        if byte == expected {
            self&.index = self&.index + 1
            if self&.index == byte_length(&self&.expected) {
                self&.found = true;
                self&.index = 0
            }
        } else {
            self&.index = 0
        }
    }
    .flush = (.self: $&Output) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()
    ) {}
)
