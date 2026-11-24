const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "401X_virtual_isolation_undeclared_delegate" {
    const path = "tests/feature_tests/concurrency/401X_virtual_isolation_undeclared_delegate";
    try support.expectFrontendFailure(path, "isolated virtual implementation cannot access a virtual operation without a checked cross-execution guarantee");
}
