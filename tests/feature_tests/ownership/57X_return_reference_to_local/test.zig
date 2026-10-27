const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/57X_return_reference_to_local" {
    try buildExpectFail("tests/feature_tests/ownership/57X_return_reference_to_local", "local storage generation");
}
