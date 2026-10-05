..invalid_hex

_digit(.byte: UInt8) -> (.value: UInt8 = 255) := {
    if byte >= 48 and byte <= 57 { value = byte - 48 }
    if byte >= 65 and byte <= 70 { value = byte - 65 + 10 }
    if byte >= 97 and byte <= 102 { value = byte - 97 + 10 }
}

-- Lowercase output, with checked capacity. Text and bytes never alias output.
encode(
        .bytes     : ArrayViewRO#(.t: UInt8),
        .allocator : $&Allocator              = reach allocator
    ) -> (
        .result : Errable#(String, (..out_of_memory, ..out_of_range))
    ) := {
    assume allocator
    count ::= length(&bytes).count
    size ::= checked_multiply(.left = count, .right = 2)!
    text ::= string_with_length(.allocator = allocator, .length = size)!
    alphabet: StringView = "0123456789abcdef"
    index :: UIntNative = 0

    while index < count {
        byte ::= unwrap_or_abort(.value = get(.self = &bytes, .index = index))
        bytes_set(
            .string = $&text
            .index  = index * 2
            .value  = bytes_get(
                .view  = &alphabet
                .index = UIntNative(
                    .value = [
                        byte
                        / 16
                    ]
                )
            ).byte
        )
        bytes_set(
            .string = $&text
            .index  = index * 2 + 1
            .value  = bytes_get(
                .view  = &alphabet
                .index = UIntNative(
                    .value = [
                        byte
                        % 16
                    ]
                )
            ).byte
        )
        index = index + 1
    }

    result = ..ok ~text
}

-- Validate completely before allocating or publishing any decoded bytes.
decode(
        .text      : StringView,
        .allocator : $&Allocator = reach allocator
    ) -> (
        .result : Errable#(DynamicArray#(.t: UInt8), (..invalid_hex, ..out_of_memory))
    ) := {
    assume allocator

    if text.length % 2 != 0 {
        result = ..error(.reason = ..invalid_hex)
        return
    }

    index :: UIntNative = 0

    while index < text.length {
        if _digit(.byte = bytes_get(.view = &text, .index = index).byte).value == 255 {
            result = ..error(.reason = ..invalid_hex)
            return
        }
        index = index + 1
    }

    bytes ::= DynamicArray#(.t: UInt8)(.allocator = allocator, .capacity = text.length / 2)!
    index = 0

    while index < text.length {
        high ::= _digit(.byte = bytes_get(.view = &text, .index = index).byte).value
        low ::= _digit(.byte = bytes_get(.view = &text, .index = index + 1).byte).value
        push_assume_capacity(.self = $&bytes, .value = high * 16 + low)
        index = index + 2
    }

    result = ..ok ~bytes
}
