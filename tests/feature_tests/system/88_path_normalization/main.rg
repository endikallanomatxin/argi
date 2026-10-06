check(.input: StringView, .expected: StringView, .allocator: $&Allocator) -> (
    .result : Errable#(.t: Void, .reasons: (..invalid_path, ..out_of_memory, ..test_failed)) = ..ok Void()
) := {
    assume allocator
    path ::= normalize_path(.view = input, .allocator = allocator)!
    expect(.condition = as_view(.self = &path) == expected)!
}
run_main(.system: System) -> (
    .result : Errable#(.t: Void, .reasons: (..invalid_path, ..out_of_memory, ..test_failed)) = ..ok Void()
) := {
    assume allocator := system.page_allocator
    check(.input = "", .expected = ".", .allocator = allocator)!
    check(.input = "a/./b/../c//", .expected = "a/c", .allocator = allocator)!
    check(.input = "a/../../b", .expected = "../b", .allocator = allocator)!
    check(.input = "/../../a", .expected = "/a", .allocator = allocator)!
    check(.input = "../..", .expected = "../..", .allocator = allocator)!
    check(.input = "a/..", .expected = ".", .allocator = allocator)!
    #if target_os("windows") {
        check(.input = "C:/a/../b", .expected = "C:/b", .allocator = allocator)!
        check(.input = "C:a/../b", .expected = "C:b", .allocator = allocator)!
        check(
            .input     = "//server/share/a/../../b",
            .expected  = "//server/share/b",
            .allocator = allocator
        )!
    }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
