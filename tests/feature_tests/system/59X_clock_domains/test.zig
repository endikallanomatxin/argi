const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/59X_clock_domains" {
    try buildExpectFail("tests/feature_tests/system/59X_clock_domains", "no function named 'elapsed' accepts arguments (.start: UnixTimestamp, .end: MonotonicInstant)");
}
