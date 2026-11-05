const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 159_bounded_callback_access" {
    try support.expectSuccessfulBuild("tests/feature_tests/c_interop/159_bounded_callback_access");
    try support.runExpect("tests/feature_tests/c_interop/159_bounded_callback_access", 0);
}
