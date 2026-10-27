const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/contracts/279_scalar_equality_evidence" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/279_scalar_equality_evidence");
    try runExpect("tests/feature_tests/contracts/279_scalar_equality_evidence", 0);
    try vmExpect("tests/feature_tests/contracts/279_scalar_equality_evidence", 0, null);
}
