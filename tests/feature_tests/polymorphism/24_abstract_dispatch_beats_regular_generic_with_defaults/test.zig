const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/24_abstract_dispatch_beats_regular_generic_with_defaults" {
    const test_path = "tests/feature_tests/polymorphism/24_abstract_dispatch_beats_regular_generic_with_defaults";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 1);
}
