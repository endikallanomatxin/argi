const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/54_deinit_through_alias_reinitialize" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/54_deinit_through_alias_reinitialize");
}
