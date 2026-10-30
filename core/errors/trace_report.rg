write_trace_text := (.text: &CChar, .writer: $&Virtual#(Writer)) -> (
    .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
) {

    bytes ::= _c_string_bytes(.text = text)
    i :: UIntNative = 0

    while i < length(&bytes).count {
        byte ::= unwrap_or_abort(.value = get(&bytes, .index = i))
        Writer#().write_byte(writer, .byte = byte)!
        i = i + 1
    }

    result = ..ok Void()
}

write_trace_uint := (.value: UIntNative, .writer: $&Virtual#(Writer)) -> (
    .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
) {

    divisor :: UIntNative = 1

    while divisor <= value / 10 { divisor = divisor * 10 }
    remaining ::= value
    digits ::= "0123456789"

    while divisor > 0 {
        digit ::= remaining / divisor
        remaining = remaining % divisor
        Writer#(
        ).write_byte(
            writer, .byte = unwrap_or_abort(.value = bytes_get(.view = &digits, .index = digit))
        )!
        divisor = divisor / 10
    }

    result = ..ok Void()
}

_error_report_entry := (
    .self: $&FixedSizeErrorTracer, .index: UIntNative, .writer: $&Virtual#(Writer)
) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))) {

    entry ::= _error_trace_load_entry(self, .index = index)
    location ::= source_location(.id = entry.location).location
    write_trace_text(.text = "  at ", .writer = writer)!
    write_trace_text(.text = location.source_file, .writer = writer)!
    write_trace_text(.text = ":", .writer = writer)!
    write_trace_uint(.value = location.line, .writer = writer)!
    write_trace_text(.text = ":", .writer = writer)!
    write_trace_uint(.value = location.column, .writer = writer)!
    slot_offset ::= index * _error_trace_stride().size
    offset ::= slot_offset + size_of(.type = ErrorTraceEntry)

    if entry.context_length != 0 {
        write_trace_text(.text = ": ", .writer = writer)!
        i :: UIntNative = 0
        while i < entry.context_length {
            byte ::= unwrap_or_abort(.value = get(&self&._buffer, .index = offset + i))
            Writer#().write_byte(writer, .byte = byte)!
            i = i + 1
        }
    }

    write_trace_text(.text = "\n    ", .writer = writer)!
    write_trace_text(.text = location.source_line, .writer = writer)!
    write_trace_text(.text = "\n    ", .writer = writer)!
    column :: UIntNative = 1

    while column < location.column {
        Writer#().write_byte(writer, .byte = 32)!
        column = column + 1
    }

    write_trace_text(.text = "^\n", .writer = writer)!

    result = ..ok Void()
}

report_trace := #(.WriterType: Type: Writer#(WriterType)) (
    .tracer: $&Virtual#(ErrorTracer), .writer: $&WriterType
) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))) {

    virtual_writer ::= to_virtual#(.contract: Writer)(.value = writer)
    ErrorTracer#().report(tracer, .writer = $&virtual_writer)!

    result = ..ok Void()
}

_ReportError#(.Payload: Type): Contract = (
    .report : (.error: &Payload, .writer: $&Virtual#(Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    )
)

implement#(.Reasons: Type) _ReportError#(Error#(Reasons)) (
    .report = (.error: &Error#(Reasons), .writer: $&Virtual#(Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        write_trace_text(.text = "error\n", .writer = writer)!
        result = ..ok Void()
    }
)

implement#(.Reasons: Type) _ReportError#(ErrorWithTrace#(Reasons)) (
    .report = (.error: &ErrorWithTrace#(Reasons), .writer: $&Virtual#(Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        ErrorTracer#().report(.self = error&.tracer, .writer = writer)!
        result = ..ok Void()
    }
)

report_error := #(.Payload: Type, .WriterType: Type: Writer#(WriterType)) (
    .err: &Payload, .writer: $&WriterType
) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))) {
    virtual_writer ::= to_virtual#(.contract: Writer)(.value = writer)
    result = _ReportError#(Payload).report(.error = err, .writer = $&virtual_writer)
}

report_error_message := #(.reasons: Type, .WriterType: Type: Writer#(WriterType)) (
    .message: &CChar, .err: &ErrorWithTrace#(.reasons: reasons), .writer: $&WriterType
) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))) {

    virtual_writer ::= to_virtual#(.contract: Writer)(.value = writer)
    write_trace_text(.text = "error: ", .writer = $&virtual_writer)!
    write_trace_text(.text = message, .writer = $&virtual_writer)!
    write_trace_text(.text = "\n", .writer = $&virtual_writer)!
    report_trace(.tracer = err&.tracer, .writer = writer)!

    result = ..ok Void()
}
