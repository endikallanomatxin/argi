const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/67_generic_nominal_policy_overloads" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/67_generic_nominal_policy_overloads");
    try runExpect("tests/feature_tests/polymorphism/67_generic_nominal_policy_overloads", 0);
}
