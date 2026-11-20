const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;

test "299_nested_slot_load_copies_final_referent" {
    const path = "tests/feature_tests/concurrency/299_nested_slot_load_copies_final_referent";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
