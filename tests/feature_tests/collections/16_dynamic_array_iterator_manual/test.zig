const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/16_dynamic_array_iterator_manual" {
    const test_path = "tests/feature_tests/collections/16_dynamic_array_iterator_manual";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
