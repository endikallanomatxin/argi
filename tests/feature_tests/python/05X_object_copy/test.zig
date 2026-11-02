const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/python/05X_object_copy" {
    try expectFrontendFailure("tests/feature_tests/python/05X_object_copy", "cannot be copied implicitly");
}
