const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop adapts overlapping numeric union arguments and results" {
    const target = @import("builtin").target;
    try support.checkNativeCFixture("tests/feature_tests/c_interop/38_numeric_union_abi", if (target.cpu.arch == .x86_64) &.{
        "declare i64 @argi_c_union_number(i64)",
        "declare float @argi_c_union_single(float)",
        "declare { <2 x float>, float } @argi_c_union_floats(<2 x float>, float)",
        "declare { double, float } @argi_c_union_mixed(double, float)",
        "sret({ [4 x double] }) align 8",
        "byval({ [3 x float] }) align 8",
    } else if (target.os.tag.isDarwin()) &.{
        "declare { float } @argi_c_union_single([1 x float])",
        "declare { float, float, float } @argi_c_union_floats([3 x float])",
        "declare { double, double, double, double } @argi_c_union_doubles([4 x double])",
        "declare [2 x i64] @argi_c_union_mixed([2 x i64])",
    } else &.{
        "declare { float } @argi_c_union_single([1 x float] alignstack(8))",
        "declare { float, float, float } @argi_c_union_floats([3 x float] alignstack(8))",
        "declare { double, double, double, double } @argi_c_union_doubles([4 x double] alignstack(8))",
        "declare [2 x i64] @argi_c_union_mixed([2 x i64])",
    });
}
