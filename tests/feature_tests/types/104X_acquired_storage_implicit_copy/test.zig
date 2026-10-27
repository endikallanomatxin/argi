const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/104X_acquired_storage_implicit_copy" {
    try expectFrontendFailure("tests/feature_tests/types/104X_acquired_storage_implicit_copy", "type 'AcquiredStorage' cannot be copied implicitly");
}
