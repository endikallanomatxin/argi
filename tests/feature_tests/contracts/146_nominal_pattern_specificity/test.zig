const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/146_nominal_pattern_specificity" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/146_nominal_pattern_specificity");
}
