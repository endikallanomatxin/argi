const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/164_stale_pointer_identity_is_allowed" {
    const test_path = "tests/feature_tests/ownership/164_stale_pointer_identity_is_allowed";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
