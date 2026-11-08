const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "426X_checked_array_element_local_escape" {
    try support.expectFrontendFailure("tests/feature_tests/types/426X_checked_array_element_local_escape", "function output cannot depend on a local storage generation");
}
