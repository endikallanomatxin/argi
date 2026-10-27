const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/36X_nested_private_submodule" {
    try buildExpectFailWithoutNoise("tests/feature_tests/modules/36X_nested_private_submodule", "submodule '_detail' is private", "panic");
}
