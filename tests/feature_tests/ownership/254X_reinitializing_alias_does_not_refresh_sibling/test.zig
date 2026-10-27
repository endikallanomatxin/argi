const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/254X_reinitializing_alias_does_not_refresh_sibling" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/254X_reinitializing_alias_does_not_refresh_sibling",
        "reference depends on a root that has ended",
    );
}
