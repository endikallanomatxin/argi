const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/68_error_tracer_bounded_failures" {
    const path = "tests/feature_tests/types/68_error_tracer_bounded_failures";
    try expectSuccessfulBuild(path);
    try run(path);
}
