const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/83_handle_owner" {
    try expectSuccessfulBuild("tests/feature_tests/errors/83_handle_owner");
    try runExpect("tests/feature_tests/errors/83_handle_owner", 0);
}
