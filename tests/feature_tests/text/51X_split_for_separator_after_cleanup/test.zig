const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/51X_split_for_separator_after_cleanup" {
    try expectFrontendFailure("tests/feature_tests/text/51X_split_for_separator_after_cleanup", "root that has ended");
}
