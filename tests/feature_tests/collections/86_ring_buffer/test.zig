const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/86_ring_buffer" {
    const path = "tests/feature_tests/collections/86_ring_buffer";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
