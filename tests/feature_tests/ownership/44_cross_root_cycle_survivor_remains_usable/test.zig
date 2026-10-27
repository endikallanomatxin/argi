const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/44_cross_root_cycle_survivor_remains_usable" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/44_cross_root_cycle_survivor_remains_usable");
}
