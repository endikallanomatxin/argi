main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    walker ::= DirectoryWalker(
        .self      = system.file_system
        .path      = "tests/feature_tests/system/86_word_count_consumer/data"
        .allocator = allocator
    )!
    count :: UIntNative = 0
    nested :: UIntNative = 0
    while true {
        match next(.self = $&walker, .allocator = allocator)! {
            ..none { break } ..some ~entry {
                if [
                    entry.value.depth
                    > 2
                ] { abort }
                if entry.value.depth == 2 { nested = nested + 1 }
                count = [
                    count
                    + 1
                ]
            }
        }
    }
    if count != 5 or nested != 1 { abort }
    match next(.self = $&walker, .allocator = allocator)! { ..none {} ..some ~_ { abort } }
    zero ::= DirectoryWalker(
        .self          = system.file_system
        .path          = "does-not-exist"
        .maximum_depth = 0
        .allocator     = allocator
    )!
    match next(.self = $&zero, .allocator = allocator)! { ..none {} ..some ~_ { abort } }
}
