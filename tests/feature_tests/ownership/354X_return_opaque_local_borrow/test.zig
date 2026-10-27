const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/354X_return_opaque_local_borrow" {
    try buildExpectFail("tests/feature_tests/ownership/354X_return_opaque_local_borrow", "local storage generation");
}
