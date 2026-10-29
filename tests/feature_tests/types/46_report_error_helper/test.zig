const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectStderr = support.runExpectStderr;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/46_report_error_helper" {
    const test_path = "tests/feature_tests/types/46_report_error_helper";
    try expectSuccessfulBuild(test_path);
    try runExpectStderr(test_path, 0,
        \\error: project build failed
        \\error trace (most recent first):
        \\  at tests/feature_tests/types/46_report_error_helper/main.rg:37:22: loading project config
        \\        value := middle()!! "loading project config"
        \\                         ^
        \\  at tests/feature_tests/types/46_report_error_helper/main.rg:24:20
        \\        value := fail()!
        \\                       ^
        \\  at tests/feature_tests/types/46_report_error_helper/main.rg:12:14
        \\        result = ..error(.reason = ..test_error)
        \\                 ^
        \\
    );
}
