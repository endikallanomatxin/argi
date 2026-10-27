const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/testing/07_build_ignores_tests" {
    const test_path = "tests/feature_tests/testing/07_build_ignores_tests";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
