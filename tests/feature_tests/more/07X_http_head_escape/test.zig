const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/more/07X_http_head_escape" {
    try support.expectFrontendFailure("tests/feature_tests/more/07X_http_head_escape", "function output cannot depend on a local storage generation that ends before return");
}
