const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/302_virtual_capture_partial_output_fields" {
    const path = "tests/feature_tests/polymorphism/302_virtual_capture_partial_output_fields";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
