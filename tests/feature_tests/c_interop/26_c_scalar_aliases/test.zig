const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop resolves target scalar aliases" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/26_c_scalar_aliases", &.{
        "declare i32 @argi_c_int(i32)",
        "declare double @argi_c_double(double)",
    });
}
