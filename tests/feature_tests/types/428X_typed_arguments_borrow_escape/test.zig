const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/428X_typed_arguments_borrow_escape" {
    try support.expectFrontendFailure("tests/feature_tests/types/428X_typed_arguments_borrow_escape", "function output cannot depend on a local storage generation");
}
