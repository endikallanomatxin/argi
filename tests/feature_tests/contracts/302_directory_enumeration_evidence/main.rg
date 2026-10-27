RefusingAllocator: Type = ()

implement Allocator#(RefusingAllocator) (
    .allocate = (.self: $&RefusingAllocator, .size: UIntNative, .alignment: UIntNative) -> (
        .result: Errable#(Allocation, (..out_of_memory))
    ) {
        result = ..error(.reason = ..out_of_memory)
    }
)

advance_directory := #(.State: Type, .Provider: Type: Allocator#(Provider)) (
    .self: $&State, .allocator: $&Provider
) -> (.result: DirectoryEnumeration#(State, Provider).Result) {
    result = ~DirectoryEnumeration#(State, Provider).next(.self = self, .allocator = allocator)
}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer := $&system.terminal&.stderr
    assume allocator := system.page_allocator
    root: StringView = "tests/feature_tests/system/86_word_count_consumer/data"
    directory ::= Directory(.self = system.file_system, .path = root)!!!
    match advance_directory(.self = $&directory, .allocator = allocator)!!! {
        ..none { abort }
        ..some ~entry {
            item: DirectoryEnumeration#(Directory, PageAllocator).Item = ~entry.value
            if byte_length(&item.name).count == 0 { abort }
        }
    }

    failing_directory ::= Directory(.self = system.file_system, .path = root)!!!
    refusing ::= RefusingAllocator()
    match advance_directory(.self = $&failing_directory, .allocator = $&refusing) {
        ..ok ~entry { abort }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }

    walker ::= DirectoryWalker(.self = system.file_system, .path = root, .maximum_depth = 0)!!!
    match advance_directory(.self = $&walker, .allocator = allocator)!!! {
        ..none {}
        ..some ~entry { abort }
    }
    match next(.self = $&walker)!!! {
        ..none {}
        ..some ~entry { abort }
    }
    status_code = 0
}
