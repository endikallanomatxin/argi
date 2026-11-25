const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "isolated callback initializes opaque owner without cleanup" {
    const path = "tests/feature_tests/c_interop/404_isolated_callback_initializes_opaque_owner";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
