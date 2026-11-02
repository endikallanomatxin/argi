const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/logging/03X_logger_writer_lifetime" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/logging/03X_logger_writer_lifetime", "function output cannot depend on a local storage generation that ends before return");
}
