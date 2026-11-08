const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "187X_returned_array_element_unknown_alternative" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/187X_returned_array_element_unknown_alternative", "pending execution");
}
