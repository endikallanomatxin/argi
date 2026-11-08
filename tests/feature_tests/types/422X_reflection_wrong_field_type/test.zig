const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/422X_reflection_wrong_field_type" {
    try support.expectFrontendFailure("tests/feature_tests/types/422X_reflection_wrong_field_type", "record builder must return the declared field type");
}
