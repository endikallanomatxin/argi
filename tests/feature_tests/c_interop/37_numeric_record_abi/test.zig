const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop adapts floating and mixed record arguments and results" {
    const target = @import("builtin").target;
    try support.checkNativeCFixture("tests/feature_tests/c_interop/37_numeric_record_abi", if (target.cpu.arch == .x86_64) &.{
        "declare float @argi_c_one(float)",
        "declare { <2 x float>, float } @argi_c_floats(<2 x float>, float)",
        "declare { i32, double } @argi_c_mixed(i32, double)",
        "declare { double, i32 } @argi_c_reverse(double, i32)",
        "byval({ float, float, float }) align 8",
        "sret({ [4 x double] }) align 8",
    } else if (target.os.tag.isDarwin()) &.{
        "declare { float } @argi_c_one([1 x float])",
        "declare { float, float, float } @argi_c_floats([3 x float])",
        "declare { double, double, double, double } @argi_c_doubles([4 x double])",
        "declare [2 x i64] @argi_c_mixed([2 x i64])",
    } else &.{
        "declare { float } @argi_c_one([1 x float] alignstack(8))",
        "declare { float, float, float } @argi_c_floats([3 x float] alignstack(8))",
        "declare { double, double, double, double } @argi_c_doubles([4 x double] alignstack(8))",
        "declare [2 x i64] @argi_c_mixed([2 x i64])",
    });
}
