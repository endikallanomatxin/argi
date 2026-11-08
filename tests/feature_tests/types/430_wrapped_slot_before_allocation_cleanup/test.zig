const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "430_wrapped_slot_before_allocation_cleanup" {
    const path = "tests/feature_tests/types/430_wrapped_slot_before_allocation_cleanup";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
