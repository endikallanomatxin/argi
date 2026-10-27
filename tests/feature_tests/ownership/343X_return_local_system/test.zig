const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/343X_return_local_system" {
    try buildExpectFail("tests/feature_tests/ownership/343X_return_local_system", "local storage generation");
}
