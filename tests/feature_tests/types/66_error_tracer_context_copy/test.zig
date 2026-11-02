const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectStderr = support.runExpectStderr;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/66_error_tracer_context_copy" {
    const path = "tests/feature_tests/types/66_error_tracer_context_copy";
    try expectSuccessfulBuild(path);
    try runExpectStderr(path, 0,
        \\error trace (most recent first):
        \\  at tests/feature_tests/types/66_error_tracer_context_copy/main.rg:23:11: AB
        \\        fail()!! view
        \\              ^
        \\  at tests/feature_tests/types/66_error_tracer_context_copy/main.rg:5:21
        \\        result = ..error(.reason = ..copy_test_failure)
        \\                        ^
        \\
    );
}
