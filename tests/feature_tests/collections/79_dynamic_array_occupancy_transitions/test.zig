const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/79_dynamic_array_occupancy_transitions" {
    const path = "tests/feature_tests/collections/79_dynamic_array_occupancy_transitions";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
