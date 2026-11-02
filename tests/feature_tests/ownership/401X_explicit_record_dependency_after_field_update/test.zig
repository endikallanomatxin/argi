const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/401X_explicit_record_dependency_after_field_update" {
    try support.expectFrontendFailure(
        "tests/feature_tests/ownership/401X_explicit_record_dependency_after_field_update",
        "value depends on a root that has ended",
    );
}
