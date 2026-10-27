const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop adapts integer record arguments and results" {
    const x64 = @import("builtin").target.cpu.arch == .x86_64;
    try support.checkNativeCFixture("tests/feature_tests/c_interop/34_integer_record_abi", if (x64) &.{
        "declare i64 @argi_c_pair(i64)",
        "declare { i64, i64 } @argi_c_words(i64, i64)",
        "byval({ i64, i64 }) align 8",
        "sret({ i64, i64, i64 }) align 8",
        "define i24 @argi_c_tiny_export(i24",
    } else &.{
        "declare i64 @argi_c_pair(i64)",
        "declare [2 x i64] @argi_c_words([2 x i64])",
        "sret({ i64, i64, i64 }) align 8",
        "define i24 @argi_c_tiny_export(i64",
    });
}
