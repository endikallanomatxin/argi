const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 149_restricted_loan_completion" {
    const path = "tests/feature_tests/concurrency/149_restricted_loan_completion";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
