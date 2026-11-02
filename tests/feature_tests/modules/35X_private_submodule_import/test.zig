const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/35X_private_submodule_import" {
    try buildExpectFailWithoutNoise("tests/feature_tests/modules/35X_private_submodule_import", "submodule '_detail' is private", "panic");
}
