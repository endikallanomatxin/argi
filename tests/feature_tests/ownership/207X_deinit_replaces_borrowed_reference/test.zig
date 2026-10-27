const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/207X_deinit_replaces_borrowed_reference" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/ownership/207X_deinit_replaces_borrowed_reference", "method 'deinit' violates its safety contract");
}
