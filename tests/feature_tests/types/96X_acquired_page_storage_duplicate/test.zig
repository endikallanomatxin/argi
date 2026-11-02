const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/96X_acquired_page_storage_duplicate" {
    try expectFrontendFailure("tests/feature_tests/types/96X_acquired_page_storage_duplicate", "was moved and cannot be used again");
}
