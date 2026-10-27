const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/142_repeated_array_length_specialization" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/142_repeated_array_length_specialization");
}
