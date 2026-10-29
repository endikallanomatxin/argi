check := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .input        : StringView,
    .expected     : StringView,
    .allocator    : $&AllocatorType,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (
    .result : Errable#(.t: Void, .reasons: (..invalid_path, ..out_of_memory, ..test_failed)) = ..ok Void(
    )
) {
    assume error_tracer

    assume allocator
    path ::= normalize_path(.view = input, .allocator = allocator)!
    expect(.condition = view(.self = &path) == expected)!
}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    check(.input = "", .expected = ".", .allocator = allocator)!!!
    check(.input = "a/./b/../c//", .expected = "a/c", .allocator = allocator)!!!
    check(.input = "a/../../b", .expected = "../b", .allocator = allocator)!!!
    check(.input = "/../../a", .expected = "/a", .allocator = allocator)!!!
    check(.input = "../..", .expected = "../..", .allocator = allocator)!!!
    check(.input = "a/..", .expected = ".", .allocator = allocator)!!!
    #if target_os("windows") {
        check(.input = "C:/a/../b", .expected = "C:/b", .allocator = allocator)!!!
        check(.input = "C:a/../b", .expected = "C:b", .allocator = allocator)!!!
        check(
            .input     = "//server/share/a/../../b"
            .expected  = "//server/share/b"
            .allocator = allocator
        )!!!
    }
    status_code = 0
}
