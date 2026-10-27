const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop adapts raw pointer arrays and union alternatives" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/42_raw_pointer_aggregate_abi", if (@import("builtin").target.cpu.arch == .x86_64) &.{
        "declare { i64, i64 } @argi_c_pointers_get()",
        "declare i64 @argi_c_address_get()",
        "declare { i64, i64 } @argi_c_alternatives_get()",
        "byval({ [2 x { i64 }] }) align 8",
        "sret({ [2 x { { i64 }, i64 }] }) align 8",
    } else &.{
        "declare [2 x i64] @argi_c_pointers_get()",
        "declare i64 @argi_c_address_get()",
        "declare [2 x i64] @argi_c_alternatives_get()",
        "sret({ [2 x { { i64 }, i64 }] }) align 8",
    });
}
