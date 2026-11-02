const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/04_string_buffer_helpers" {
    const test_path = "tests/feature_tests/text/04_string_buffer_helpers";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
