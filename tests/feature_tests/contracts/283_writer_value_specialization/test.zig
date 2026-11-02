const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/283_writer_value_specialization" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/283_writer_value_specialization");
    try runExpect("tests/feature_tests/contracts/283_writer_value_specialization", 0);
}
