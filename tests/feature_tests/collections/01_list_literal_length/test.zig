const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/01_list_literal_length" {
    const test_path = "tests/feature_tests/collections/01_list_literal_length";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
