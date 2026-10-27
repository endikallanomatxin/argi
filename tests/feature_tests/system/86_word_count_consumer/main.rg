words ::= import ("../../../usecase_tests/03_word_count/library")

expect_count := (
    .self: &HashMap#(.key: String, .value: UIntNative, .policy: StandardHashPolicy),
    .word      : StringView,
    .expected  : UIntNative,
    .allocator : $&PageAllocator
) -> !Void = ..ok Void() {
    assume allocator
    key ::= format(.value = word)!
    match get_reference(.self = self, .key = view(&key)).result {
        ..none { abort }
        ..some borrowed { if borrowed.value&!= expected { abort } }
    }
}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    counts ::= HashMap#(.key: String, .value: UIntNative, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!!!
    scratch :: [4]UInt8 = (0, 0, 0, 0)
    words.count_directory(
        .self        = $&counts
        .path        = "tests/feature_tests/system/86_word_count_consumer/data"
        .limit       = 64
        .buffer      = view(.self = $&scratch)
        .file_system = system.file_system
        .allocator   = allocator
    )!!!
    expect_count(.self = &counts, .word = "café", .expected = 3, .allocator = allocator)!!!
    expect_count(.self = &counts, .word = "tea", .expected = 2, .allocator = allocator)!!!
    expect_count(.self = &counts, .word = "🙂", .expected = 2, .allocator = allocator)!!!
    if length(.self = &counts).count != 3 { abort }
    invalid :: [1]UInt8 = (255)
    match string_from_bytes(.bytes = view(&invalid), .allocator = allocator) {
        ..ok ~text { abort }
        ..error error { if error.reason != ..invalid_utf8 { abort } }
    }
    if length(.self = &counts).count != 3 { abort }
    match words.count_directory(
        .self        = $&counts
        .path        = "tests/feature_tests/system/86_word_count_consumer/data"
        .limit       = 1
        .buffer      = view(.self = $&scratch)
        .file_system = system.file_system
        .allocator   = allocator
    ) {
        ..ok _ { abort }
        ..error error { if error.reason != ..size_limit_exceeded { abort } }
    }
    expect_count(.self = &counts, .word = "café", .expected = 3, .allocator = allocator)!!!
    status_code = 0
}
