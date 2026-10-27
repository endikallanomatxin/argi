const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/99X_acquired_storage_consumed_forwarding" {
    try expectFrontendFailure("tests/feature_tests/types/99X_acquired_storage_consumed_forwarding", "was moved and cannot be used again");
}
