const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "407X_raw_virtual_deallocation_private" {
    const path = "tests/feature_tests/concurrency/407X_raw_virtual_deallocation_private";
    try support.expectFrontendFailure(path, "contract operation is private to its defining module");
}
