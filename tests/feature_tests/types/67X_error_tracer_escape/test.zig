const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/67X_error_tracer_escape" {
    try buildExpectFail("tests/feature_tests/types/67X_error_tracer_escape", "local storage generation");
}
