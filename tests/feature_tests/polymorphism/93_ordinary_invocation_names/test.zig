const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/polymorphism/93_ordinary_invocation_names" {
    const path = "tests/feature_tests/polymorphism/93_ordinary_invocation_names";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
