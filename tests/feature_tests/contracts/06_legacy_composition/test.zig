const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/06_legacy_composition" {
    const test_path = "tests/feature_tests/contracts/06_legacy_composition";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
