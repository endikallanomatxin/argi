_string_copy_view_into(.output: $&String, .offset: UIntNative, .source: StringView) -> () := {
    index :: UIntNative = 0

    while index < source.length {
        bytes_set(
            .string = output
            .index  = offset + index
            .value  = bytes_get(.view = &source, .index = index).byte
        )
        index = index + 1
    }
}

join(
        .parts     : ArrayViewRO#(.t: StringView),
        .separator : StringView,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(String, (..out_of_memory, ..size_overflow))
    ) := {
    limit ::= _string_max_result_length().length
    count ::= length(&parts).count
    total :: UIntNative = 0
    index :: UIntNative = 0
    -- Inspect lengths before allocating or reading any text bytes. Each sum
    -- is checked by subtraction, including the trailing-NUL reservation.
    while index < count {
        part ::= unwrap_or_abort(.value = get_ro_ref(.self = &parts, .index = index))&
        if part.length > limit - total {
            result = ..error(.reason = ..size_overflow)
            return
        }
        total = total + part.length
        if index > 0 {
            if separator.length > limit - total {
                result = ..error(.reason = ..size_overflow)
                return
            }
            total = total + separator.length
        }
        index = index + 1
    }

    output ::= string_with_length(.allocator = allocator, .length = total)!
    offset :: UIntNative = 0
    index = 0

    while index < count {
        if index > 0 {
            _string_copy_view_into(.output = $&output, .offset = offset, .source = separator)
            offset = offset + separator.length
        }
        part ::= unwrap_or_abort(.value = get_ro_ref(.self = &parts, .index = index))&
        _string_copy_view_into(.output = $&output, .offset = offset, .source = part)
        offset = offset + part.length
        index = index + 1
    }

    result = ..ok ~output
}
