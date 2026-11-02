const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/73_error_tracer_shared_log" {
    const path = "tests/feature_tests/types/73_error_tracer_shared_log";
    try expectSuccessfulBuild(path);
    try run(path);
}
