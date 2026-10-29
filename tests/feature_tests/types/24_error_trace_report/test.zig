const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectStderr = support.runExpectStderr;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/24_error_trace_report" {
    const test_path = "tests/feature_tests/types/24_error_trace_report";
    try expectSuccessfulBuild(test_path);
    try runExpectStderr(test_path, 0,
        \\error trace (most recent first):
        \\  at tests/feature_tests/types/24_error_trace_report/main.rg:25:22: reading config
        \\        value := middle()!! "reading config"
        \\                         ^
        \\  at tests/feature_tests/types/24_error_trace_report/main.rg:16:20
        \\        value := fail()!
        \\                       ^
        \\  at tests/feature_tests/types/24_error_trace_report/main.rg:8:14
        \\        result = ..error(.reason = ..test_error)
        \\                 ^
        \\
    );
}
