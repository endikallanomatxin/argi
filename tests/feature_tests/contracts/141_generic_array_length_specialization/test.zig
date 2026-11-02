const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/141_generic_array_length_specialization" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/141_generic_array_length_specialization");
    try runExpect("tests/feature_tests/contracts/141_generic_array_length_specialization", 0);
}
