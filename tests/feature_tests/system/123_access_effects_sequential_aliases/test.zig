const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "access effects preserve sequential mutable aliases" {
    const path = "tests/feature_tests/system/123_access_effects_sequential_aliases";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 42);
    try support.vmExpect(path, 42, null);
}
