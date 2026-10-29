..invalid_hex

_digit := (.byte: UInt8) -> (.value: UInt8 = 255) {
    if byte >= 48 and byte <= 57 { value = byte - 48 }
    if byte >= 65 and byte <= 70 { value = byte - 65 + 10 }
    if byte >= 97 and byte <= 102 { value = byte - 97 + 10 }
}

-- Lowercase output, with checked capacity. Text and bytes never alias output.
encode := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .bytes        : ArrayView#(.t: UInt8),
    .allocator    : $&AllocatorType,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(String, (..out_of_memory, ..out_of_range))) {
    assume error_tracer

    assume allocator
    count ::= length(&bytes).count
    size ::= checked_multiply(.left = count, .right = 2)!
    text ::= string_with_length(.allocator = allocator, .length = size)!
    alphabet: StringView = "0123456789abcdef"
    index :: UIntNative = 0

    while index < count {
        byte ::= unwrap_or_abort(.value = get(.self = &bytes, .index = index))
        _ ::= unwrap_or_abort(
            .value = set_ascii(
                .self  = $&text
                .index = index * 2
                .byte  = unwrap_or_abort(
                    .value = bytes_get(
                        .view = &alphabet, .index = [byte / 16] | convert#(.to: UIntNative)(_)
                    )
                )
            )
        )
        _ ::= unwrap_or_abort(
            .value = set_ascii(
                .self  = $&text
                .index = index * 2 + 1
                .byte  = unwrap_or_abort(
                    .value = bytes_get(
                        .view = &alphabet, .index = [byte % 16] | convert#(.to: UIntNative)(_)
                    )
                )
            )
        )
        index = index + 1
    }

    result = ..ok ~text
}

-- Validate completely before allocating or publishing any decoded bytes.
decode := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .text         : StringView,
    .allocator    : $&AllocatorType,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(DynamicArray#(.t: UInt8), (..invalid_hex, ..out_of_memory))) {
    assume error_tracer

    assume allocator

    if byte_length(&text).count % 2 != 0 {
        result = ..error(.reason = ..invalid_hex)
        return
    }

    index :: UIntNative = 0

    while index < byte_length(&text).count {
        if [
            _digit(
                .byte = unwrap_or_abort(.value = bytes_get(.view = &text, .index = index))
            ).value
            == 255
        ] {
            result = ..error(.reason = ..invalid_hex)
            return
        }
        index = index + 1
    }

    bytes ::= DynamicArray#(.t: UInt8)(
        .allocator = allocator, .capacity = [byte_length(&text).count / 2]
    )!
    index = 0

    while index < byte_length(&text).count {
        high ::= _digit(
            .byte = unwrap_or_abort(.value = bytes_get(.view = &text, .index = index))
        ).value
        low ::= _digit(
            .byte = unwrap_or_abort(.value = bytes_get(.view = &text, .index = [index + 1]))
        ).value
        push_assume_capacity(.self = $&bytes, .value = high * 16 + low)
        index = index + 2
    }

    result = ..ok ~bytes
}
