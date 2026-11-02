const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/322X_caller_storage_forwarding" {
    try expectFrontendFailure("tests/feature_tests/ownership/322X_caller_storage_forwarding", "local storage generation");
}
