const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/280_linear_algebra_add_evidence" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/280_linear_algebra_add_evidence");
    try runExpect("tests/feature_tests/contracts/280_linear_algebra_add_evidence", 0);
}
