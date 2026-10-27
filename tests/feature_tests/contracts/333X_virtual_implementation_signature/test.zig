const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/333X_virtual_implementation_signature" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/333X_virtual_implementation_signature", "implementation-defined operation signatures require static selection and cannot be virtualized", "panic");
}
