const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/56_branch_ownership_cleanup_resolves" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/56_branch_ownership_cleanup_resolves");
}
