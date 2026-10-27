const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/338X_partial_constructor_unknown_parameter" {
    try buildExpectFail("tests/feature_tests/contracts/338X_partial_constructor_unknown_parameter", "unknown compile-time parameter in constructor");
}
