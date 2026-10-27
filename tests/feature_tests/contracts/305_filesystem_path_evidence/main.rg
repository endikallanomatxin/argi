RefusingAllocator: Type = ()

implement Allocator#(RefusingAllocator) (
    .allocate = (.self: $&RefusingAllocator, .size: UIntNative, .alignment: UIntNative) -> (
        .result: Errable#(Allocation, (..out_of_memory))
    ) {
        result = ..error(.reason = ..out_of_memory)
    }
)

borrowed_exists := #(.P: Type: PathExistence#(P)) (.self: &FileSystem, .path: P) -> (
    .ok : PathExistence#(P).Result
) {
    ok = PathExistence#(P).exists(.self = self, .path = path)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator := system.page_allocator
    text: StringView = "tests/feature_tests/system/86_word_count_consumer/data"
    c_path ::= from_literal(.data = "tests/feature_tests/system/86_word_count_consumer/data")
    if borrowed_exists(.self = system.file_system, .path = c_path) == false { status_code = 1 }
    string ::= unwrap_or_abort(
        .value = string_with_capacity(
            .allocator = allocator, .capacity = byte_length(&text).count
        )
    )
    unwrap_or_abort(.value = push_view(.self = $&string, .view = text, .allocator = allocator))
    if borrowed_exists(.self = system.file_system, .path = &string) == false {
        status_code = 2
    }
    path ::= Path(.text = ~string)
    if borrowed_exists(.self = system.file_system, .path = &path) == false { status_code = 3 }
    if unwrap_or_abort(.value = exists(.self = system.file_system, .path = text)) == false {
        status_code = 4
    }
    refusing ::= RefusingAllocator()
    match exists(.self = system.file_system, .path = text, .allocator = $&refusing) {
        ..ok _ { status_code = 5 }
        ..error error { if error.reason != ..out_of_memory { status_code = 6 } }
    }
    match remove(.self = system.file_system, .path = text, .allocator = $&refusing) {
        ..ok _ { status_code = 7 }
        ..error error { if error.reason != ..out_of_memory { status_code = 8 } }
    }
    match rename(.self = system.file_system, .from = text, .to = text, .allocator = $&refusing) {
        ..ok _ { status_code = 9 }
        ..error error { if error.reason != ..out_of_memory { status_code = 10 } }
    }
    content ::= unwrap_or_abort(.value = String(.allocator = allocator))
    match write_file(
        .self = system.file_system, .path = text, .text = &content, .allocator = $&refusing
    ) {
        ..ok _ { status_code = 11 }
        ..error error { if error.reason != ..out_of_memory { status_code = 12 } }
    }
}
