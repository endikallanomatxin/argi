const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/317X_storage_capability_forwarded_shared_outputs" {
    try expectFrontendFailure("tests/feature_tests/ownership/317X_storage_capability_forwarded_shared_outputs", "already been consumed");
}
