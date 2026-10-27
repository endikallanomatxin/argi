const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/359X_return_local_error_trace" {
    try buildExpectFail("tests/feature_tests/ownership/359X_return_local_error_trace", "local storage generation");
}
