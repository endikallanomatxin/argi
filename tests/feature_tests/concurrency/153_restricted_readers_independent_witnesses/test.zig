const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 153_restricted_readers_independent_witnesses" {
    const path = "tests/feature_tests/concurrency/153_restricted_readers_independent_witnesses";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
