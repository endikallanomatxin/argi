const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "nested region does not authorize siblings" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/377X_nested_region_sibling_overclaim", "memory access exceeds the declared reads/writes bounds");
}
