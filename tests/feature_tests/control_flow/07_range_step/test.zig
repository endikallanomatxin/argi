const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/07_range_step" {
    const test_path = "tests/feature_tests/control_flow/07_range_step";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
