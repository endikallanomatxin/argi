const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/35_generic_specialization_cache_nominal_identity" {
    const test_path = "tests/feature_tests/polymorphism/35_generic_specialization_cache_nominal_identity";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 12);
}
