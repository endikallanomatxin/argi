const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/59X_clock_domains" {
    try expectFrontendFailure("tests/feature_tests/system/59X_clock_domains", "no function named 'elapsed' accepts arguments (.start: UnixTimestamp, .end: MonotonicInstant)");
}
