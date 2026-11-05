const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 75_completed_call_restores_entry_authority" {
    const path = "tests/feature_tests/concurrency/75_completed_call_restores_entry_authority";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
