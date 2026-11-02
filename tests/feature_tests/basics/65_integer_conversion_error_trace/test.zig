const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/65_integer_conversion_error_trace" {
    const path = "tests/feature_tests/basics/65_integer_conversion_error_trace";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
