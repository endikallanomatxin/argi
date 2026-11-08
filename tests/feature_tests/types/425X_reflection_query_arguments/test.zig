const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/425X_reflection_query_arguments" {
    try support.expectFrontendFailure("tests/feature_tests/types/425X_reflection_query_arguments", "is_choice_type requires one '.type = T' argument");
}
