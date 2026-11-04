const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 16_borrowed_pair_fields" {
    const path = "tests/feature_tests/concurrency/16_borrowed_pair_fields";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
