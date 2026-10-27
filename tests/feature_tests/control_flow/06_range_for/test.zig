const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/06_range_for" {
    const test_path = "tests/feature_tests/control_flow/06_range_for";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
