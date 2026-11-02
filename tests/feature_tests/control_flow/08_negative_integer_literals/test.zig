const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/08_negative_integer_literals" {
    const test_path = "tests/feature_tests/control_flow/08_negative_integer_literals";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
