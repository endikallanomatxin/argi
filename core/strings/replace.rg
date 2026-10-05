replace(
        .self        : StringView,
        .pattern     : StringView,
        .replacement : StringView,
        .allocator   : $&Allocator,
    ) -> (
        .result : Errable#(String, (..out_of_memory, ..size_overflow, ..empty_pattern))
    ) := {
    if pattern.length == 0 {
        result = ..error(.reason = ..empty_pattern)
        return
    }

    limit ::= _string_max_result_length().length
    parts ::= unwrap_or_abort(.value = split(.self = self, .separator = pattern))
    first ::= true
    total :: UIntNative = 0
    -- Splitting visits non-overlapping matches. Measure before reserving
    -- storage, then copy into a fresh buffer so overlapping inputs are safe.
    while has_next(&parts).ok {
        segment ::= next($&parts).value
        if first == false {
            if replacement.length > limit - total {
                result = ..error(.reason = ..size_overflow)
                return
            }
            total = total + replacement.length
        }
        if segment.length > limit - total {
            result = ..error(.reason = ..size_overflow)
            return
        }
        total = total + segment.length
        first = false
    }

    output ::= string_with_length(.allocator = allocator, .length = total)!
    remaining ::= unwrap_or_abort(.value = split(.self = self, .separator = pattern))
    first = true
    offset :: UIntNative = 0

    while has_next(&remaining).ok {
        segment ::= next($&remaining).value
        if first == false {
            _string_copy_view_into(.output = $&output, .offset = offset, .source = replacement)
            offset = offset + replacement.length
        }
        _string_copy_view_into(.output = $&output, .offset = offset, .source = segment)
        offset = offset + segment.length
        first = false
    }

    result = ..ok ~output
}
