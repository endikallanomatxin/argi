const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/315X_storage_capability_local_pointer_write" {
    try expectFrontendFailure("tests/feature_tests/ownership/315X_storage_capability_local_pointer_write", "already been consumed");
}
