const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 357X_legacy_region_mapping" {
    try support.expectSyntaxFailure("tests/feature_tests/polymorphism/357X_legacy_region_mapping", "legacy implementation storage mappings are unsupported");
}
