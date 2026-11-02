const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/92_handle_abort" {
    try expectSuccessfulBuild("tests/feature_tests/errors/92_handle_abort");
    try runExpectFailure("tests/feature_tests/errors/92_handle_abort");
}
