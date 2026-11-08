const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "427X_generic_array_element_aggregate_escape" {
    try support.expectFrontendFailure("tests/feature_tests/types/427X_generic_array_element_aggregate_escape", "function output cannot depend on a local storage generation");
}
