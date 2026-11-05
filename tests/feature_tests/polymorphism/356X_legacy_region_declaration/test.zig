const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 356X_legacy_region_declaration" {
    try support.expectSyntaxFailure("tests/feature_tests/polymorphism/356X_legacy_region_declaration", "legacy storage domains are unsupported");
}
