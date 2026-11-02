const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/26_error_reason_superset_propagation" {
    const test_path = "tests/feature_tests/types/26_error_reason_superset_propagation";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
