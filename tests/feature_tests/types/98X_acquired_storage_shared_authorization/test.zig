const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/98X_acquired_storage_shared_authorization" {
    try expectFrontendFailure("tests/feature_tests/types/98X_acquired_storage_shared_authorization", "was moved and cannot be used again");
}
