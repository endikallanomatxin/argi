const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/70_virtual_context_inference" {
    const path = "tests/feature_tests/types/70_virtual_context_inference";
    try expectSuccessfulBuild(path);
    try run(path);
}
