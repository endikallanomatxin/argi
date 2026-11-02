const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/09_mutable_and_read_alias_same_call" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/09_mutable_and_read_alias_same_call");
}
