const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/237_init_owned_policy_failure_cleanup" {
    const path = "tests/feature_tests/contracts/237_init_owned_policy_failure_cleanup";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
