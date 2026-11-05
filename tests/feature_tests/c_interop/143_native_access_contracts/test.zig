const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop native access contracts" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/143_native_access_contracts", &.{
        "declare i32 @argi_access_read(ptr",
        "declare void @argi_access_write(ptr",
        "declare i32 @argi_access_abs(i32",
    });
}
