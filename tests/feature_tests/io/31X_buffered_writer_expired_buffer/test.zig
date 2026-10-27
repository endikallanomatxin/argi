const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/31X_buffered_writer_expired_buffer" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/io/31X_buffered_writer_expired_buffer", "reference depends on a root that has ended");
}
