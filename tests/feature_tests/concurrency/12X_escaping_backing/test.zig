const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 12X_escaping_backing" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/12X_escaping_backing", "root");
}
