const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/36X_utf8_after_storage" {
    try expectFrontendFailure("tests/feature_tests/text/36X_utf8_after_storage", "root that has ended");
}
