const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/87_ring_buffer_ownership" {
    const path = "tests/feature_tests/collections/87_ring_buffer_ownership";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
