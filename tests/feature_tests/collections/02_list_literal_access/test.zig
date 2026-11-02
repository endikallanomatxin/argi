const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/02_list_literal_access" {
    const test_path = "tests/feature_tests/collections/02_list_literal_access";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
