const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/34_error_propagation_runs_auto_deinit" {
    const test_path = "tests/feature_tests/ownership/34_error_propagation_runs_auto_deinit";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
