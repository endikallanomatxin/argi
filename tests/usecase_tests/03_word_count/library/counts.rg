count_text(
        .self      : $&OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy),
        .text      : StringView,
        .allocator : $&PageAllocator
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..invalid_utf8, ..out_of_memory, ..out_of_range)) = ..ok Void()
    ) := {
    assume allocator

    validate_utf8(text)!
    iterator ::= split_whitespace(text)

    while has_next(&iterator).ok {
        token ::= next($&iterator).value
        match get_ref(.self = self, .key = token).result {
            ..none {
                word ::= format(token)!
                put(.self = self, .key = ~word, .value = 1)!
            }
            ..some borrowed {
                borrowed.value&= checked_add(borrowed.value&, 1)!
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
    assume file_system

    directory ::= Directory(.path = path)!

    while true {
        match next($&directory)! {
            ..none { return }
            ..some ~payload {
                joined ::= String(.capacity = 16)!
                push_view(.self = $&joined, .view = path)!
                push_byte(.self = $&joined, .byte = 47)!
                push_view(
                    .self = $&joined
                    .view = as_view(&payload.value.name)
                )!

                info ::= metadata(.path = as_view(&joined), .self = file_system)!
                if info.kind == ..file {
                    file ::= open_read(
                        .self = file_system
                        .path = as_view(&joined)
                    )!

                    text ::= read_all_limited(
                        .self   = $&file
                        .buffer = buffer
                        .limit  = limit
                    )!

                    count_text(
                        .self = self
                        .text = as_view(&text)
                    )!
                }
            }
        }
    }
}
