const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectStderr = support.runExpectStderr;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/19_print_error_borrowed_string_view" {
    const test_path = "tests/feature_tests/io/19_print_error_borrowed_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpectStderr(test_path, 0, "borrowed err");
}
