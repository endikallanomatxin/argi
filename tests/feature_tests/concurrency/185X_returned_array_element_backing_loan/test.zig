const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "185X_returned_array_element_backing_loan" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/185X_returned_array_element_backing_loan", "pending execution");
}
