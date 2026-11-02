const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/294_virtual_capture_forwarded_initialization" {
    const path = "tests/feature_tests/polymorphism/294_virtual_capture_forwarded_initialization";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
