main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    walker ::= DirectoryWalker(
        .self      = system.file_system
        .path      = "tests/feature_tests/system/86_word_count_consumer/data"
        .allocator = allocator
    )!!!
    count :: UIntNative = 0
    nested :: UIntNative = 0
    while true {
        match next(.self = $&walker, .allocator = allocator)!!! {
            ..none { break } ..some ~entry {
                if [entry.value.depth > 2] { abort }
                if entry.value.depth == 2 { nested = nested + 1 }
                count = [count + 1]
            }
        }
    }
    if count != 5 or nested != 1 { abort }
    match next(.self = $&walker, .allocator = allocator)!!! { ..none {} ..some ~_ { abort } }
    zero ::= DirectoryWalker(
        .self          = system.file_system
        .path          = "does-not-exist"
        .maximum_depth = 0
        .allocator     = allocator
    )!!!
    match next(.self = $&zero, .allocator = allocator)!!! { ..none {} ..some ~_ { abort } }
    #if target_os("linux") or target_os("macos") {
        assume file_system := system.file_system
        temporary ::= TemporaryDirectory(
            .parent = "tests/feature_tests/system/93_directory_walk/build"
        )!!!
        original ::= path(.self = &temporary).view
        child ::= concat(.left = original, .right = "/child", .allocator = allocator)!!!
        moved ::= concat(.left = original, .right = "-moved", .allocator = allocator)!!!
        create_directory(.path = view(&child))!!!
        changed ::= DirectoryWalker(.path = original, .allocator = allocator)!!!
        _ ::= rename(
            .self = file_system, .from = original, .to = view(&moved), .allocator = allocator
        )!!!
        match next(.self = $&changed, .allocator = allocator) {
            ..ok ~_ { abort }
            ..error error { if error.reason != ..path_not_found { abort } }
        }
        match next(.self = $&changed, .allocator = allocator)!!! {
            ..none {} ..some ~_ { abort }
        }
        deinit(.self = $&changed)
        _ ::= rename(
            .self = file_system, .from = view(&moved), .to = original, .allocator = allocator
        )!!!
        remove_directory(.path = view(&child))!!!
        close(.self = $&temporary)!!!
    }
    status_code = 0
}
