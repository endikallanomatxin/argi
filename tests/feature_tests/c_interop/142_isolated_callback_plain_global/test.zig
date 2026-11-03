const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "isolated callback accepts plain global" {
    const path = "tests/feature_tests/c_interop/142_isolated_callback_plain_global";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 42);
}
