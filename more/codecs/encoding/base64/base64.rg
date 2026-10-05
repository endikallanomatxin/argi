..invalid_base64

_alphabet() -> (.text: StringView) := {
    text = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
}

_value(.byte: UInt8) -> (.value: UInt32 = 255) := {
    if byte >= 65 and byte <= 90 {
        value = UInt32(.value = byte - 65)
        return
    }

    if byte >= 97 and byte <= 122 {
        value = UInt32(.value = byte - 97) + 26
        return
    }

    if byte >= 48 and byte <= 57 {
        value = UInt32(.value = byte - 48) + 52
        return
    }

    if byte == 43 { value = 62 }
    if byte == 47 { value = 63 }
}

-- RFC 4648 standard alphabet with required padding; no inserted whitespace.
encode(
        .bytes     : ArrayViewRO#(.t: UInt8),
        .allocator : $&Allocator              = reach allocator
    ) -> (
        .result : Errable#(String, (..out_of_memory, ..out_of_range))
    ) := {
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
        a ::= UInt32(.value = unwrap_or_abort(.value = get(.self = &bytes, .index = index)))
        b :: UInt32 = 0
        c :: UInt32 = 0
        if count - index > 1 {
            b = UInt32(
                .value = unwrap_or_abort(
                    .value = get(
                        .self  = &bytes
                        .index = [
                            index
                            + 1
                        ]
                    )
                )
            )
        }
        if count - index > 2 {
            c = UInt32(
                .value = unwrap_or_abort(
                    .value = get(
                        .self  = &bytes
                        .index = [
                            index
                            + 2
                        ]
                    )
                )
            )
        }
        bytes_set(
            .string = $&text
            .index  = output
            .value  = bytes_get(
                .view  = &alphabet
                .index = UIntNative(
                    .value = [
                        a
                        / 4
                    ]
                )
            ).byte
        )
        bytes_set(
            .string = $&text
            .index  = output + 1
            .value  = bytes_get(
                .view  = &alphabet
                .index = UIntNative(
                    .value = [
                        [a % 4] * 16
                        + b / 16
                    ]
                )
            ).byte
        )
        third :: UInt8 = 61
        fourth :: UInt8 = 61
        if count - index > 1 {
            third = bytes_get(
                .view  = &alphabet
                .index = UIntNative(
                    .value = [
                        [b % 16] * 4
                        + c / 64
                    ]
                )
            ).byte
        }
        if count - index > 2 {
            fourth = bytes_get(
                .view  = &alphabet
                .index = UIntNative(
                    .value = [
                        c
                        % 64
                    ]
                )
            ).byte
        }
        bytes_set(.string = $&text, .index = output + 2, .value = third)
        bytes_set(.string = $&text, .index = output + 3, .value = fourth)
        -- The final partial group must not form an index beyond native size.
        if count - index <= 3 { break }
        index = index + 3
        output = output + 4
    }

    result = ..ok ~text
}

-- Reject misplaced padding, whitespace and nonzero unused trailing bits.
-- Validation precedes allocation, so malformed input publishes no prefix.
decode(
        .text      : StringView,
        .allocator : $&Allocator = reach allocator
    ) -> (
        .result : Errable#(DynamicArray#(.t: UInt8), (..invalid_base64, ..out_of_memory))
    ) := {
    assume allocator

    if text.length % 4 != 0 {
        result = ..error(.reason = ..invalid_base64)
        return
    }

    count ::= text.length / 4 * 3
    padding :: UIntNative = 0

    if text.length > 0 {
        if bytes_get(.view = &text, .index = text.length - 1).byte == 61 { padding = 1 }
        if bytes_get(.view = &text, .index = text.length - 2).byte == 61 { padding = padding + 1 }
    }

    index :: UIntNative = 0

    while index < text.length - padding {
        if _value(.byte = bytes_get(.view = &text, .index = index).byte).value == 255 {
            result = ..error(.reason = ..invalid_base64)
            return
        }
        index = index + 1
    }

    if padding > 0 {
        last ::= _value(.byte = bytes_get(.view = &text, .index = text.length - padding - 1).byte).value
        if [padding == 2 and last % 16 != 0] or [padding == 1 and last % 4 != 0] {
            result = ..error(.reason = ..invalid_base64)
            return
        }
    }

    bytes ::= DynamicArray#(.t: UInt8)(.allocator = allocator, .capacity = count - padding)!
    index = 0

    while index < text.length {
        a ::= _value(.byte = bytes_get(.view = &text, .index = index).byte).value
        b ::= _value(.byte = bytes_get(.view = &text, .index = index + 1).byte).value
        c ::= _value(.byte = bytes_get(.view = &text, .index = index + 2).byte).value
        d ::= _value(.byte = bytes_get(.view = &text, .index = index + 3).byte).value
        push_assume_capacity(
            .self  = $&bytes
            .value = unwrap_or_abort(
                .value = UInt8(
                    .value = [
                        a * 4
                        + b / 16
                    ]
                )
            )
        )
        if c != 255 {
            push_assume_capacity(
                .self  = $&bytes
                .value = unwrap_or_abort(
                    .value = UInt8(
                        .value = [
                            [b % 16] * 16
                            + c / 4
                        ]
                    )
                )
            )
        }
        if d != 255 {
            push_assume_capacity(
                .self  = $&bytes
                .value = unwrap_or_abort(
                    .value = UInt8(
                        .value = [
                            [c % 4] * 64
                            + d
                        ]
                    )
                )
            )
        }
        index = index + 4
    }

    result = ..ok ~bytes
}
