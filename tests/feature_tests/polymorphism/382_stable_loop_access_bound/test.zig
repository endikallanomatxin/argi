const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism/382_stable_loop_access_bound" {
    try support.expectSuccessfulBuild("tests/feature_tests/polymorphism/382_stable_loop_access_bound");
    try support.runExpect("tests/feature_tests/polymorphism/382_stable_loop_access_bound", 0);
}
