const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/133X_ordinary_identity_across_files" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/133X_ordinary_identity_across_files", "ordinary function 'same_name' has more than one declaration", "panic");
}
