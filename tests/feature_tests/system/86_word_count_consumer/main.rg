words ::= import ("../../../usecase_tests/03_word_count/library")

expect_count(
        .self      : &OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy),
        .word      : StringView,
        .expected  : UIntNative,
        .allocator : $&PageAllocator
    ) -> !Void = ..ok Void() := {
    assume allocator
    key ::= format(.value = word)!
    match get_ro_ref(.self = self, .key = &key).result {
        ..none { abort }
        ..some borrowed { if borrowed.value&!= expected { abort } }
    }
}

run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    counts ::= OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy)(
        .policy    = StringHashPolicy()
        .allocator = allocator
    )!
    scratch :: [4]UInt8 = (0, 0, 0, 0)
    words.count_directory(
        .self        = $&counts
        .path        = "tests/feature_tests/system/86_word_count_consumer/data"
        .limit       = 64
        .buffer      = view(.array = $&scratch)
        .file_system = system.file_system
        .allocator   = allocator
    )!
    expect_count(.self = &counts, .word = "café", .expected = 3, .allocator = allocator)!
    expect_count(.self = &counts, .word = "tea", .expected = 2, .allocator = allocator)!
    expect_count(.self = &counts, .word = "🙂", .expected = 2, .allocator = allocator)!
    if length(.self = &counts).count != 3 { abort }
    invalid :: [1]UInt8 = (255)
    bad :: StringView = (.data = &invalid[0], .length = 1)
    match words.count_text(.self = $&counts, .text = bad, .allocator = allocator) {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_utf8 { abort } }
    }
    if length(.self = &counts).count != 3 { abort }
    match words.count_directory(
        .self        = $&counts
        .path        = "tests/feature_tests/system/86_word_count_consumer/data"
        .limit       = 1
        .buffer      = view(.array = $&scratch)
        .file_system = system.file_system
        .allocator   = allocator
    ) {
        ..ok _ { abort }
        ..error error { if error.reason != ..size_limit_exceeded { abort } }
    }
    expect_count(.self = &counts, .word = "café", .expected = 3, .allocator = allocator)!
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
