const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/355X_return_borrowed_opaque_local" {
    try buildExpectFail("tests/feature_tests/ownership/355X_return_borrowed_opaque_local", "local storage generation");
}
