const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;

test "293_root_array_backing_independent_loan" {
    const path = "tests/feature_tests/concurrency/293_root_array_backing_independent_loan";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
