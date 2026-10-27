const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/133X_ordinary_identity_across_files" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/133X_ordinary_identity_across_files", "ordinary function 'same_name' has more than one declaration", "panic");
}
