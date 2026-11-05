const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism/376X_nested_region_nonterminal" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/376X_nested_region_nonterminal", "terminal projection");
}
