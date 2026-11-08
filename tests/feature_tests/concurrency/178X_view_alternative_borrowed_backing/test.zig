const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "178X_view_alternative_borrowed_backing" {
    try support.expectFrontendFailure(
        "tests/feature_tests/concurrency/178X_view_alternative_borrowed_backing",
        "pending execution",
    );
}
