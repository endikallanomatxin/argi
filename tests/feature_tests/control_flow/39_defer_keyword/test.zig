const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/39_defer_keyword" {
    try expectSuccessfulBuild("tests/feature_tests/control_flow/39_defer_keyword");
    try run("tests/feature_tests/control_flow/39_defer_keyword");
}
