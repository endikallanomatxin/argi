DecimalBuffer := (
    .bytes : [32]UInt8 = (
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0
    )
    .length : UIntNative = 0
)

main := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> (.status_code: Int32 = 0) {
    assume error_tracer
    allocator ::= system.page_allocator
    index :: UInt32 = 0
    buffer ::= DecimalBuffer()
    -- Every finite binary16 encoding, including both zeros and all subnormals.
    while index < 65536 {
        bits ::= unwrap_or_abort(.value = index | convert#(.to: UInt16)(_)).result
        if bits % 32768 < 31744 {
            original ::= trusted_reinterpret_reference#(.from: UInt16, .to: Float16)(
                .base = &bits
            ).reference&
            buffer.length = 0
            unwrap_or_abort(
                .value = WriteValue#(
                    DecimalBuffer, Float16
                ).write_value(.self = $&buffer, .value = original)
            )
            bytes ::= unwrap_or_abort(
                .value = slice(&view(&buffer.bytes), .start = 0, .count = buffer.length)
            )
            text ::= unwrap_or_abort(
                .value = string_from_bytes(.bytes = bytes, .allocator = allocator)
            )
            view ::= view(&text)
            parsed ::= unwrap_or_abort(.value = parse_float16(.text = view)).result
            parsed_bits ::= trusted_reinterpret_reference#(.from: Float16, .to: UInt16)(
                .base = &parsed
            ).reference&
            if parsed_bits != bits { abort }
        }
        index = index + 1
    }
}

implement Writer#(DecimalBuffer) (
    .write_byte = (.self: $&DecimalBuffer, .byte: UInt8, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume error_tracer

        if self&.length == 32 { abort }
        self&.bytes[self&.length] = byte
        self&.length = self&.length + 1
        result = ..ok Void()
    }

    .flush = (.self: $&DecimalBuffer, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume error_tracer

        abort
    }
)
