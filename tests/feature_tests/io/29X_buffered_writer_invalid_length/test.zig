const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/29X_buffered_writer_invalid_length" {
    const test_path = "tests/feature_tests/io/29X_buffered_writer_invalid_length";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}
