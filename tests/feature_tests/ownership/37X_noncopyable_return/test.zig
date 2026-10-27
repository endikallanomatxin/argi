const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/37X_noncopyable_return" {
    try buildExpectFail("tests/feature_tests/ownership/37X_noncopyable_return", "cannot be copied implicitly");
}
