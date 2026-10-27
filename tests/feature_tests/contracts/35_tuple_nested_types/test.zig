const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/35_tuple_nested_types" {
    const test_path = "tests/feature_tests/contracts/35_tuple_nested_types";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
