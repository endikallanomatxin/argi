count_text(
        .self      : $&OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy),
        .text      : StringView,
        .allocator : $&PageAllocator
    ) -> !Void = ..ok Void() := {
    assume allocator

    validate_utf8(text)!

    for token in split_whitespace(text) {
        match get_ref(self, token).result {
            ..none {
                word ::= format(token)!
                put(self, ~word, 1)!
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
    ) -> !Void = ..ok Void() := {
    assume allocator
    assume file_system

    directory ::= Directory(.path = path)!! path

    while true {
        match next($&directory)!! path {
            ..none { return }
            ..some ~entry {
                name ::= as_view(&entry.value.name)
                joined ::= join_views(&path, &name)!
                full_path ::= as_view(&joined)
                info ::= metadata(file_system, full_path)!! full_path

                if info.kind == ..file {
                    file_reader ::= open_read(file_system, full_path)!! full_path
                    text ::= read_all_limited($&file_reader, buffer, limit)!! full_path
                    close($&file_reader)!! full_path

                    count_text(self, as_view(&text))!! full_path
                }
            }
        }
    }
}
