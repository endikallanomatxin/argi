const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/301_virtual_capture_nested_output" {
    const path = "tests/feature_tests/polymorphism/301_virtual_capture_nested_output";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
