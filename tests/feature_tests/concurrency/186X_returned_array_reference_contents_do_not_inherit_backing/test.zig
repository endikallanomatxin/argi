const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "186X_returned_array_reference_contents_do_not_inherit_backing" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/186X_returned_array_reference_contents_do_not_inherit_backing", "pending execution");
}
