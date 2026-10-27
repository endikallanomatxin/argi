const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/88_ring_buffer_errors" {
    const path = "tests/feature_tests/collections/88_ring_buffer_errors";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
