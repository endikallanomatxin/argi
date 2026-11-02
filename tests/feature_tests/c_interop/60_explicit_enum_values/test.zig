const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop preserves explicit enum values across modules and caching" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/60_explicit_enum_values", &.{
        "define i32 @argi_enum_next(i32",
        "i32 -2147483648",
        "i32 2147483647",
    });
}
