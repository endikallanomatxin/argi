const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/96X_atomic_copy" {
    try expectFrontendFailure("tests/feature_tests/system/96X_atomic_copy", "cannot be copied implicitly");
}
