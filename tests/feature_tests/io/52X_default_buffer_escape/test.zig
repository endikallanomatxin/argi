const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/52X_default_buffer_escape" {
    try buildExpectFail("tests/feature_tests/io/52X_default_buffer_escape", "function output cannot depend on a local storage generation");
}
