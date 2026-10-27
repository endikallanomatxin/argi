const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/01_if" {
    const test_path = "tests/feature_tests/control_flow/01_if";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
