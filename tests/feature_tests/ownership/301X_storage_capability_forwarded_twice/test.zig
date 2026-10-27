const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/301X_storage_capability_forwarded_twice" {
    try expectFrontendFailure("tests/feature_tests/ownership/301X_storage_capability_forwarded_twice", "already been consumed");
}
