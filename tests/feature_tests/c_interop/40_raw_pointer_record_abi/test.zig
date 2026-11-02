const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop adapts raw pointer fields without accepting safe reference fields" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/40_raw_pointer_record_abi", if (@import("builtin").target.cpu.arch == .x86_64) &.{
        "declare { i64, i64 } @argi_c_buffer_get()",
        "declare { i64, float } @argi_c_buffer_weighted(i64, float)",
        "byval({ { i64 }, i64 }) align 8",
        "sret({ { i64 }, i64, { i64 } }) align 8",
    } else &.{
        "declare [2 x i64] @argi_c_buffer_get()",
        "declare [2 x i64] @argi_c_buffer_weighted([2 x i64])",
        "sret({ { i64 }, i64, { i64 } }) align 8",
    });
}
