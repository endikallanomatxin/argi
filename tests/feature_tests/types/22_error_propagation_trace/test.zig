const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/22_error_propagation_trace" {
    const test_path = "tests/feature_tests/types/22_error_propagation_trace";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
