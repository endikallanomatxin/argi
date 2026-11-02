const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/290_virtual_capture_same_call_initialization" {
    const path = "tests/feature_tests/polymorphism/290_virtual_capture_same_call_initialization";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
