const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "associated function values with operation expressions" {
    const path = "tests/feature_tests/contracts/354_associated_function_values";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
