-- Lexical normalization removes repeated separators and dot components. It
-- never follows links or queries FileSystem; a normalized path is not a
-- containment proof. Relative leading parents remain, rooted parents clamp
-- at the root, and Windows drive-relative prefixes retain their meaning.
normalize_path := <.AllocatorType: Type: Allocator<AllocatorType>> (
    .view: StringView, .allocator: $&AllocatorType = reach allocator
) -> (.result: Errable<Path, (..invalid_path, ..out_of_memory)>) {
    assume allocator
    index :: UIntNative = 0

    while index < view._length {
        if unwrap_or_abort(.value = bytes_get(.view = &view, .index = index)) == 0 {
            result = ..error(.reason = ..invalid_path)
            return
        }
        index = index + 1
    }

    root ::= _platform_path_root_length(.view = &view).length
    prefix ::= root
    #if target_os("windows") {
        if view._length >= 2 {
            a ::= unwrap_or_abort(.value = bytes_get(.view = &view, .index = 0))
            b ::= unwrap_or_abort(.value = bytes_get(.view = &view, .index = 1))
            if path_is_separator(.byte = a).ok and path_is_separator(.byte = b).ok and root <= 1 {
                result = ..error(.reason = ..invalid_path)
                return
            }
            if prefix == 0 and b == 58 and [[a >= 65 and a <= 90] or [a >= 97 and a <= 122]] {
                prefix = 2
            }
        }
    }

    parts ::= DynamicArray<.t: StringView>(.allocator = allocator, .capacity = 1)!
    index = prefix

    while index < view._length {
        while index < view._length {
            if [
                path_is_separator(
                    .byte = unwrap_or_abort(.value = bytes_get(.view = &view, .index = index))
                ).ok
                == false
            ] {
                break
            }
            index = index + 1
        }
        start ::= index
        while index < view._length {
            if path_is_separator(
                .byte = unwrap_or_abort(.value = bytes_get(.view = &view, .index = index))
            ).ok {
                break
            }
            index = index + 1
        }
        if start == index { break }
        part ::= unwrap_or_abort(.value = slice(view, .start = start, .count = index - start))
        if part == "." { continue }
        if part == ".." {
            count ::= length(&parts).count
            if count > 0 {
                last ::= unwrap_or_abort(.value = get(&parts, .index = count - 1))
                if last != ".." {
                    removed ::= pop($&parts)
                    continue
                }
            }
            if root > 0 { continue }
        }
        push(.self = $&parts, .value = part, .allocator = allocator)!
    }

    text ::= string_with_capacity(.allocator = allocator, .capacity = view._length)!
    index = 0

    while index < prefix {
        byte ::= unwrap_or_abort(.value = bytes_get(.view = &view, .index = index))
        if path_is_separator(.byte = byte).ok { byte = 47 }
        _string_push_byte($&text, .byte = byte, .allocator = allocator)!
        index = index + 1
    }

    index = 0

    while index < length(&parts).count {
        if index > 0 or root > 0 {
            if text._length > 0 {
                if [
                    unwrap_or_abort(
                        .value = bytes_get(.view = &view(&text), .index = text._length - 1)
                    )
                    != 47
                ] {
                    _string_push_byte($&text, .byte = 47, .allocator = allocator)!
                }
            }
        }
        part ::= unwrap_or_abort(.value = get(&parts, .index = index))
        push_view($&text, .view = part, .allocator = allocator)!
        index = index + 1
    }

    if text._length == 0 { _string_push_byte($&text, .byte = 46, .allocator = allocator)! }

    result = ..ok Path(.text = ~text)
}
