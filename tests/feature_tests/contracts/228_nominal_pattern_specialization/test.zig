const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/228_nominal_pattern_specialization" {
    const path = "tests/feature_tests/contracts/228_nominal_pattern_specialization";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
