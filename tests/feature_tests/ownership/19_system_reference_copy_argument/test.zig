const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/19_system_reference_copy_argument" {
    const test_path = "tests/feature_tests/ownership/19_system_reference_copy_argument";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
