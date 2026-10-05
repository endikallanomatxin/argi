-- Lexical normalization removes repeated separators and dot components. It
-- never follows links or queries FileSystem; a normalized path is not a
-- containment proof. Relative leading parents remain, rooted parents clamp
-- at the root, and Windows drive-relative prefixes retain their meaning.
normalize_path(.view: StringView, .allocator: $&Allocator = reach allocator) -> (
    .result : Errable#(.t: Path, .reasons: (..invalid_path, ..out_of_memory))
) := {
    assume allocator
    index :: UIntNative = 0
    while index < view.length {
        if bytes_get(.view = &view, .index = index).byte == 0 {
            result = ..error(.reason = ..invalid_path) return
        }
        index = index + 1
    }
    root ::= _platform_path_root_length(.view = &view).length
    prefix ::= root
    #if target_os("windows") {
        if view.length >= 2 {
            a ::= bytes_get(.view = &view, .index = 0).byte
            b ::= bytes_get(.view = &view, .index = 1).byte
            if path_is_separator(.byte = a).ok and path_is_separator(.byte = b).ok and root <= 1 {
                result = ..error(.reason = ..invalid_path) return
            }
            if prefix == 0 and b == 58 and [[a >= 65 and a <= 90] or [a >= 97 and a <= 122]] {
                prefix = 2
            }
        }
    }
    parts ::= DynamicArray#(.t: StringView)(.allocator = allocator, .capacity = 1)!
    index = prefix
    while index < view.length {
        while index < view.length {
            if path_is_separator(.byte = bytes_get(.view = &view, .index = index).byte).ok == false {
                break
            }
            index = index + 1
        }
        start ::= index
        while index < view.length {
            if path_is_separator(.byte = bytes_get(.view = &view, .index = index).byte).ok {
                break
            }
            index = index + 1
        }
        if start == index { break }
        part ::= unwrap_or_abort(
            .value = slice(.self = view, .start = start, .count = index - start)
        )
        if part == "." { continue }
        if part == ".." {
            count ::= length(.self = &parts).count
            if count > 0 {
                last ::= unwrap_or_abort(.value = get(.self = &parts, .index = count - 1))
                if last != ".." { removed ::= pop(.self = $&parts) continue }
            }
            if root > 0 { continue }
        }
        push(.self = $&parts, .value = part, .allocator = allocator)!
    }
    text ::= string_with_capacity(.allocator = allocator, .capacity = view.length)!
    index = 0
    while index < prefix {
        byte ::= bytes_get(.view = &view, .index = index).byte
        if path_is_separator(.byte = byte).ok { byte = 47 }
        push_byte(.self = $&text, .byte = byte, .allocator = allocator)!
        index = index + 1
    }
    index = 0
    while index < length(.self = &parts).count {
        if index > 0 or root > 0 {
            if text.length > 0 {
                if bytes_get(.view = &as_view(.self = &text), .index = text.length - 1).byte != 47 {
                    push_byte(.self = $&text, .byte = 47, .allocator = allocator)!
                }
            }
        }
        part ::= unwrap_or_abort(.value = get(.self = &parts, .index = index))
        push_view(.self = $&text, .view = part, .allocator = allocator)!
        index = index + 1
    }
    if text.length == 0 { push_byte(.self = $&text, .byte = 46, .allocator = allocator)! }
    result = ..ok Path(.text = ~text)
}
