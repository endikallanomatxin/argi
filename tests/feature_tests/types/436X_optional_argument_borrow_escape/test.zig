const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/436X_optional_argument_borrow_escape" {
    try support.expectFrontendFailure("tests/feature_tests/types/436X_optional_argument_borrow_escape", "function output cannot depend on a local storage generation");
}
