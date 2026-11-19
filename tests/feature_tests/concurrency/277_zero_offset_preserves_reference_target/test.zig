const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "277_zero_offset_preserves_reference_target" {
    const path = "tests/feature_tests/concurrency/277_zero_offset_preserves_reference_target";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
