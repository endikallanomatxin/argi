const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "297_zero_offset_load_copies_immediate_referent" {
    const path = "tests/feature_tests/concurrency/297_zero_offset_load_copies_immediate_referent";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
