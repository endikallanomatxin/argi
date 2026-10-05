count_text(
        .self      : $&OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy),
        .text      : StringView,
        .allocator : $&PageAllocator
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..invalid_utf8, ..out_of_memory, ..out_of_range)) = ..ok Void()
    ) := {
    assume allocator
    validate_utf8(.text = text)!
    iterator ::= split_whitespace(.self = text)
    while has_next(.self = &iterator).ok {
        token ::= next(.self = $&iterator).value
        match get_ref(.self = self, .key = token).result {
            ..none {
                word ::= format(.value = token, .allocator = allocator)!
                put(.self = self, .key = ~word, .value = 1, .allocator = allocator)!
            }
            ..some borrowed {
                borrowed.value&= checked_add(.left = borrowed.value&, .right = 1)!
            }
        }
    }
}

count_directory(
        .self        : $&OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy),
        .path        : StringView,
        .limit       : UIntNative,
        .buffer      : ArrayView#(.t: UInt8),
        .file_system : $&FileSystem,
        .allocator   : $&PageAllocator
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
        ) = ..ok Void()
    ) := {
    assume allocator
    directory ::= Directory(.path = path, .self = file_system)!
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
                info ::= metadata(.path = as_view(.self = &joined), .self = file_system)!
                if info.kind == ..file {
                    file ::= open_read(
                        .self      = file_system
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
