const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/65_error_tracer_capability" {
    const path = "tests/feature_tests/types/65_error_tracer_capability";
    try expectSuccessfulBuild(path);
    try run(path);
}
