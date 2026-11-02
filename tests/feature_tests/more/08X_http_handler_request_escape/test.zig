const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/more/08X_http_handler_request_escape" {
    try support.expectFrontendFailure(
        "tests/feature_tests/more/08X_http_handler_request_escape",
        "caller storage cannot depend on a local storage generation that ends before return",
    );
}
