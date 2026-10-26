_string_copy_view_into := (.output: $&String, .offset: UIntNative, .source: StringView) -> () {
    index :: UIntNative = 0

    while index < source._length {
        _string_set_byte(
            .string = output
            .index  = offset + index
            .value  = unwrap_or_abort(.value = bytes_get(.view = &source, .index = index))
        )
        index = index + 1
    }
}

join := <.AllocatorType: Type: Allocator<AllocatorType>> (
    .parts: ArrayView<.t: StringView>, .separator: StringView, .allocator: $&AllocatorType
) -> (.result: Errable<String, (..out_of_memory, ..size_overflow)>) {
    limit ::= _string_max_result_length().length
    count ::= length(&parts).count
    total :: UIntNative = 0
    index :: UIntNative = 0
    -- Inspect lengths before allocating or reading any text bytes. Each sum
    -- is checked by subtraction, including the trailing-NUL reservation.
    while index < count {
        part ::= unwrap_or_abort(.value = get_reference(&parts, .index = index))&
        if part._length > limit - total {
            result = ..error(.reason = ..size_overflow)
            return
        }
        total = total + part._length
        if index > 0 {
            if separator._length > limit - total {
                result = ..error(.reason = ..size_overflow)
                return
            }
            total = total + separator._length
        }
        index = index + 1
    }

    output ::= string_with_length(.allocator = allocator, .length = total)!
    offset :: UIntNative = 0
    index = 0

    while index < count {
        if index > 0 {
            _string_copy_view_into(.output = $&output, .offset = offset, .source = separator)
            offset = offset + separator._length
        }
        part ::= unwrap_or_abort(.value = get_reference(&parts, .index = index))&
        _string_copy_view_into(.output = $&output, .offset = offset, .source = part)
        offset = offset + part._length
        index = index + 1
    }

    result = ..ok ~output
}
