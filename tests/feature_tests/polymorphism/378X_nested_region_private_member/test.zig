const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "nested region member privacy" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/378X_nested_region_private_member", "nested region mappings cannot access private regions");
}
