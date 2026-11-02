const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/288X_explicit_dependency_through_call" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/288X_explicit_dependency_through_call",
        "value depends on a root that has ended",
    );
}
