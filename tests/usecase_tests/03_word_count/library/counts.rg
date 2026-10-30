count_text := (
    .self      : $&HashMap#(.key: String, .value: UIntNative, .policy: StandardHashPolicy),
    .text      : StringView,
    .allocator : $&PageAllocator
) -> !Void = ..ok Void() {
    assume allocator

    for token in split_whitespace(text) {
        match get_mutable_reference(self, token).result {
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

count_directory := (
    .self         : $&HashMap#(.key: String, .value: UIntNative, .policy: StandardHashPolicy),
    .path         : StringView,
    .limit        : UIntNative,
    .buffer       : MutableArrayView#(.t: UInt8),
    .file_system  : $&FileSystem,
    .allocator    : $&PageAllocator,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> !!Void = ..ok Void() {
    assume error_tracer
    assume allocator
    assume file_system

    directory ::= Directory(.self = file_system, .path = path)!! path

    while true {
        match next($&directory)!! path {
            ..none { return }
            ..some ~entry {
                name ::= view(&entry.value.name)
                joined ::= join_views(&path, &name)!! path
                full_path ::= view(&joined)
                info ::= metadata(file_system, full_path)!! full_path

                if info.kind == ..file {
                    file_reader ::= open_file(
                        .file_system = file_system, .path = full_path, .mode = ..read
                    )!! full_path
                    text ::= read_all_limited($&file_reader, buffer, limit)!! full_path
                    close($&file_reader)!! full_path

                    decoded ::= string_from_bytes(.bytes = view(&text))!! full_path
                    count_text(self, view(&decoded))!! full_path
                }
            }
        }
    }
}
