const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/292_test_equality_specialization" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/292_test_equality_specialization");
    try runExpect("tests/feature_tests/contracts/292_test_equality_specialization", 0);
}
