const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/358X_return_local_expression" {
    try buildExpectFail("tests/feature_tests/ownership/358X_return_local_expression", "local storage generation");
}
