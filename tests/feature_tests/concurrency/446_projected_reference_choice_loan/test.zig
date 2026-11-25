const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "446_projected_reference_choice_loan" {
    const path = "tests/feature_tests/concurrency/446_projected_reference_choice_loan";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
