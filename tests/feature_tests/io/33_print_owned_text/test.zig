const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectStdout = support.runExpectStdout;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/33_print_owned_text" {
    const path = "tests/feature_tests/io/33_print_owned_text";
    try expectSuccessfulBuild(path);
    try runExpectStdout(path, 0, "Hello world 123\n123!\n123123\nleftright\ninline 123\n");
}
