const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "229_definite_symbolic_target_clears_old_reference" {
    const path = "tests/feature_tests/concurrency/229_definite_symbolic_target_clears_old_reference";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
