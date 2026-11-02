const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/247_ordinary_deinit_has_no_cleanup_identity" {
    const path = "tests/feature_tests/contracts/247_ordinary_deinit_has_no_cleanup_identity";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
