const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/50X_buffered_reader_after_storage" {
    try expectFrontendFailure("tests/feature_tests/io/50X_buffered_reader_after_storage", "ended");
}
