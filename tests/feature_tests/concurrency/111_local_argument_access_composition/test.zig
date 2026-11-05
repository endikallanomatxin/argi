const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 111_local_argument_access_composition" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/111_local_argument_access_composition");
    try support.runExpect("tests/feature_tests/concurrency/111_local_argument_access_composition", 0);
}
