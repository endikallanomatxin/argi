const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/101_explicit_unary_body_member" {
    const path = "tests/feature_tests/contracts/101_explicit_unary_body_member";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
