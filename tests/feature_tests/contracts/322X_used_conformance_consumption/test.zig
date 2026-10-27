const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/322X_used_conformance_consumption" {
    try expectFrontendFailure("tests/feature_tests/contracts/322X_used_conformance_consumption", "cannot prove consumes");
}
