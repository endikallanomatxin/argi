const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/60_partial_field_move_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/60_partial_field_move_cleanup");
}
