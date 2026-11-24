const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "400X_virtual_isolation_publication" {
    const path = "tests/feature_tests/concurrency/400X_virtual_isolation_publication";
    try support.expectFrontendFailure(path, "isolated virtual implementation cannot access mutable global storage");
}
