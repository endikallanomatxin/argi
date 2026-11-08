const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/424X_reflection_union_alias" {
    try support.expectFrontendFailure("tests/feature_tests/types/424X_reflection_union_alias", "field reflection does not support overlapping CUnion storage");
}
