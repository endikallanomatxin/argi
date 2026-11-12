const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "233_aliased_reference_repair" {
    const path = "tests/feature_tests/concurrency/233_aliased_reference_repair";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
