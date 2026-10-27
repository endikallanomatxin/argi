const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/logging/03X_logger_writer_lifetime" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/logging/03X_logger_writer_lifetime", "function output cannot depend on a local storage generation that ends before return");
}
