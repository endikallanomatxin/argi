..invalid_base64

_alphabet := () -> (.text: StringView) {
    text = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
}

_value := (.byte: UInt8) -> (.value: UInt32 = 255) {
    if byte >= 65 and byte <= 90 {
        value = [byte - 65] | convert#(.to: UInt32)(_)
        return
    }

    if byte >= 97 and byte <= 122 {
        value = [byte - 97] | convert#(.to: UInt32)(_) + 26
        return
    }

    if byte >= 48 and byte <= 57 {
        value = [byte - 48] | convert#(.to: UInt32)(_) + 52
        return
    }

    if byte == 43 { value = 62 }
    if byte == 47 { value = 63 }
}

-- RFC 4648 standard alphabet with required padding; no inserted whitespace.
encode := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .bytes: ArrayView#(.t: UInt8), .allocator: $&AllocatorType
) -> (.result: Errable#(String, (..out_of_memory, ..out_of_range))) {
    assume allocator
    alphabet ::= _alphabet().text
    count ::= length(&bytes).count
    groups ::= count / 3

    if count % 3 != 0 { groups = groups + 1 }
    size ::= checked_multiply(.left = groups, .right = 4)!
    text ::= string_with_length(.allocator = allocator, .length = size)!
    index :: UIntNative = 0
    output :: UIntNative = 0

    while index < count {
        a ::= [
            unwrap_or_abort(.value = get(.self = &bytes, .index = index))
            | convert#(.to: UInt32)(_)
        ]
        b :: UInt32 = 0
        c :: UInt32 = 0
        if count - index > 1 {
            b = [
                [
                    unwrap_or_abort(.value = get(.self = &bytes, .index = [index + 1]))
                ]
                | convert#(.to: UInt32)(_)
            ]
        }
        if count - index > 2 {
            c = [
                [
                    unwrap_or_abort(.value = get(.self = &bytes, .index = [index + 2]))
                ]
                | convert#(.to: UInt32)(_)
            ]
        }
        _ ::= unwrap_or_abort(
            .value = set_ascii(
                .self  = $&text
                .index = output
                .byte  = unwrap_or_abort(
                    .value = bytes_get(
                        .view = &alphabet, .index = [[a / 4] | convert#(.to: UIntNative)(_)]
                    )
                )
            )
        )
        _ ::= unwrap_or_abort(
            .value = set_ascii(
                .self  = $&text
                .index = output + 1
                .byte  = unwrap_or_abort(
                    .value = bytes_get(
                        .view  = &alphabet
                        .index = [[a % 4] * 16 + b / 16] | convert#(.to: UIntNative)(_)
                    )
                )
            )
        )
        third :: UInt8 = 61
        fourth :: UInt8 = 61
        if count - index > 1 {
            third = unwrap_or_abort(
                .value = bytes_get(
                    .view  = &alphabet
                    .index = [[b % 16] * 4 + c / 64] | convert#(.to: UIntNative)(_)
                )
            )
        }
        if count - index > 2 {
            fourth = unwrap_or_abort(
                .value = bytes_get(
                    .view = &alphabet, .index = [[c % 64] | convert#(.to: UIntNative)(_)]
                )
            )
        }
        _ ::= unwrap_or_abort(
            .value = set_ascii(.self = $&text, .index = output + 2, .byte = third)
        )
        _ ::= unwrap_or_abort(
            .value = set_ascii(.self = $&text, .index = output + 3, .byte = fourth)
        )
        -- The final partial group must not form an index beyond native size.
        if count - index <= 3 { break }
        index = index + 3
        output = output + 4
    }

    result = ..ok ~text
}

-- Reject misplaced padding, whitespace and nonzero unused trailing bits.
-- Validation precedes allocation, so malformed input publishes no prefix.
decode := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .text: StringView, .allocator: $&AllocatorType
) -> (.result: Errable#(DynamicArray#(.t: UInt8), (..invalid_base64, ..out_of_memory))) {
    assume allocator

    if byte_length(&text).count % 4 != 0 {
        result = ..error(.reason = ..invalid_base64)
        return
    }

    count ::= byte_length(&text).count / 4 * 3
    padding :: UIntNative = 0

    if byte_length(&text).count > 0 {
        if [
            unwrap_or_abort(
                .value = bytes_get(.view = &text, .index = byte_length(&text).count - 1)
            )
            == 61
        ] {
            padding = 1
        }
        if [
            unwrap_or_abort(
                .value = bytes_get(.view = &text, .index = byte_length(&text).count - 2)
            )
            == 61
        ] {
            padding = padding + 1
        }
    }

    index :: UIntNative = 0

    while index < byte_length(&text).count - padding {
        if [
            _value(
                .byte = unwrap_or_abort(.value = bytes_get(.view = &text, .index = index))
            ).value
            == 255
        ] {
            result = ..error(.reason = ..invalid_base64)
            return
        }
        index = index + 1
    }

    if padding > 0 {
        last ::= _value(
            .byte = unwrap_or_abort(
                .value = bytes_get(
                    .view = &text, .index = byte_length(&text).count - padding - 1
                )
            )
        ).value
        if [padding == 2 and last % 16 != 0] or [padding == 1 and last % 4 != 0] {
            result = ..error(.reason = ..invalid_base64)
            return
        }
    }

    bytes ::= DynamicArray#(.t: UInt8)(.allocator = allocator, .capacity = count - padding)!
    index = 0

    while index < byte_length(&text).count {
        a ::= _value(
            .byte = unwrap_or_abort(.value = bytes_get(.view = &text, .index = index))
        ).value
        b ::= _value(
            .byte = unwrap_or_abort(.value = bytes_get(.view = &text, .index = [index + 1]))
        ).value
        c ::= _value(
            .byte = unwrap_or_abort(.value = bytes_get(.view = &text, .index = [index + 2]))
        ).value
        d ::= _value(
            .byte = unwrap_or_abort(.value = bytes_get(.view = &text, .index = [index + 3]))
        ).value
        push_assume_capacity(
            .self  = $&bytes
            .value = unwrap_or_abort(.value = [a * 4 + b / 16] | convert#(.to: UInt8)(_))
        )
        if c != 255 {
            push_assume_capacity(
                .self  = $&bytes
                .value = unwrap_or_abort(
                    .value = [[[b % 16] * 16 + c / 4] | convert#(.to: UInt8)(_)]
                )
            )
        }
        if d != 255 {
            push_assume_capacity(
                .self  = $&bytes
                .value = unwrap_or_abort(.value = [[c % 4] * 64 + d] | convert#(.to: UInt8)(_))
            )
        }
        index = index + 4
    }

    result = ..ok ~bytes
}
