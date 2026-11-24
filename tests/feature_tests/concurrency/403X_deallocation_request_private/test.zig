const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "403X_deallocation_request_private" {
    const path = "tests/feature_tests/concurrency/403X_deallocation_request_private";
    try support.expectFrontendFailure(path, "field '_data' is private to its module");
}
