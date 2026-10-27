const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/07_array_index_uint_native" {
    const test_path = "tests/feature_tests/collections/07_array_index_uint_native";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
