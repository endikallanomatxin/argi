const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/291_virtual_capture_initialized_reference" {
    const path = "tests/feature_tests/polymorphism/291_virtual_capture_initialized_reference";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
