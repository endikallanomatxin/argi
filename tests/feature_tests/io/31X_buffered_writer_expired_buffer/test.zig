const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/31X_buffered_writer_expired_buffer" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/io/31X_buffered_writer_expired_buffer", "reference depends on a root that has ended");
}
