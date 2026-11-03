const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "packed calls consume once function identity" {
    try support.expectFrontendFailureWithoutParseNoise("tests/feature_tests/polymorphism/88X_packed_once_repeated", "once function 'setup' is consumed more than once");
}
