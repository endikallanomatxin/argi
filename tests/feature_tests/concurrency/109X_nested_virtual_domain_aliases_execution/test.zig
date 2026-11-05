const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 109X_nested_virtual_domain_aliases_execution" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/109X_nested_virtual_domain_aliases_execution", "concurrent access conflicts through aliased function inputs");
}
