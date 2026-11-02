const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/04_for_dynamic_array" {
    const test_path = "tests/feature_tests/control_flow/04_for_dynamic_array";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
