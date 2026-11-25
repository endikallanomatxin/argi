const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "451_summary_weak_store_keeps_live_alternatives" {
    const path = "tests/feature_tests/concurrency/451_summary_weak_store_keeps_live_alternatives";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
