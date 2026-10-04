-- Preserve bytes and case; punctuation belongs to the word.
_separator(.byte: UInt8) -> (.yes: Bool) := {
    yes = byte == 32 or byte == 9 or byte == 10 or byte == 11 or byte == 12 or byte == 13
}

count_text(
        .self      : $&OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy),
        .text      : StringView,
        .allocator : $&PageAllocator
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..invalid_utf8, ..out_of_memory, ..out_of_range))
    ) := {
    result = ..ok Void()
    assume allocator
    validate_utf8(.text = text)!
    index :: UIntNative = 0
    while index < text.length {
        if _separator(.byte = bytes_get(.view = &text, .index = index)).yes {
            index = index + 1
        } else {
            word ::= String(.allocator = allocator, .capacity = 16)!
            while index < text.length {
                byte ::= bytes_get(.view = &text, .index = index).byte
                if _separator(.byte = byte).yes { break }
                push_byte(.self = $&word, .byte = byte, .allocator = allocator)!
                index = index + 1
            }
            count :: UIntNative = 1
            match get_ro_ref(.self = self, .key = &word).result {
                ..none {}
                ..some borrowed { count = checked_add(.left = borrowed.value&, .right = 1)! }
            }
            put(.self = self, .key = ~word, .value = count, .allocator = allocator)!
        }
    }
}

count_directory(
        .self      : $&OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy),
        .path      : StringView,
        .limit     : UIntNative,
        .buffer    : ArrayView#(.t: UInt8),
        .file_sys  : $&FileSystem,
        .allocator : $&PageAllocator
    ) -> (
        .result : Errable#(
            .t       : Void,
            .reasons : (
                ..invalid_utf8,
                ..out_of_memory,
                ..out_of_range,
                ..invalid_path,
                ..path_not_found,
                ..permission_denied,
                ..already_exists,
                ..not_a_directory,
                ..filesystem_failed,
                ..path_open_failed,
                ..stream_read_failed,
                ..invalid_stream_buffer,
                ..size_limit_exceeded,
                ..size_overflow
            )
        )
    ) := {
    result = ..ok Void()
    assume allocator
    directory ::= Directory(.path = path, .self = file_sys)!
    while true {
        match next(.self = $&directory, .allocator = allocator)! {
            ..none { return }
            ..some ~payload {
                joined ::= String(.allocator = allocator, .capacity = 16)!
                push_view(.self = $&joined, .view = path, .allocator = allocator)!
                push_byte(.self = $&joined, .byte = 47, .allocator = allocator)!
                push_view(
                    .self      = $&joined
                    .view      = as_view(.self = &payload.value.name)
                    .allocator = allocator
                )!
                info ::= metadata(.path = as_view(.self = &joined), .self = file_sys)!
                if info.kind == ..file {
                    file ::= open_read(
                        .self      = file_sys
                        .path      = as_view(.self = &joined)
                        .allocator = allocator
                    )!
                    text ::= read_all_limited(
                        .self      = $&file
                        .buffer    = buffer
                        .limit     = limit
                        .allocator = allocator
                    )!
                    count_text(
                        .self      = self
                        .text      = as_view(.self = &text)
                        .allocator = allocator
                    )!
                }
            }
        }
    }
}
