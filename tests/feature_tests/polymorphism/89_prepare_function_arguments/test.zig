const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/89_prepare_function_arguments" {
    const path = "tests/feature_tests/polymorphism/89_prepare_function_arguments";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
