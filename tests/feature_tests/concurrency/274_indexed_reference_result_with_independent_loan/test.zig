const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "274_indexed_reference_result_with_independent_loan" {
    const path = "tests/feature_tests/concurrency/274_indexed_reference_result_with_independent_loan";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
