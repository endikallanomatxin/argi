const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/65X_process_stream_lifetime" {
    try expectFrontendFailure("tests/feature_tests/system/65X_process_stream_lifetime", "reference depends on a root that has ended");
}
