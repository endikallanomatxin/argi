const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/37X_noncopyable_return" {
    try expectFrontendFailure("tests/feature_tests/ownership/37X_noncopyable_return", "cannot be copied implicitly");
}
