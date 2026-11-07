const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "146_unknown_reference_shared_reader" {
    const path = "tests/feature_tests/concurrency/146_unknown_reference_shared_reader";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
