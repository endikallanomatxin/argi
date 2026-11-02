const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectStderr = support.runExpectStderr;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/69_error_tracer_truncation" {
    const path = "tests/feature_tests/types/69_error_tracer_truncation";
    try expectSuccessfulBuild(path);
    try runExpectStderr(path, 0,
        \\error trace (most recent first):
        \\  at tests/feature_tests/types/69_error_tracer_truncation/main.rg:14:21: latest
        \\        add_context_text(.context = "latest")
        \\                        ^
        \\  <context truncated>
        \\  at tests/feature_tests/types/69_error_tracer_truncation/main.rg:5:21
        \\        result = ..error(.reason = ..truncated_test_failure)
        \\                        ^
        \\
    );
}
