const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/423X_reflection_borrow_escape" {
    try support.expectFrontendFailure("tests/feature_tests/types/423X_reflection_borrow_escape", "function output cannot depend on a local storage generation");
}
