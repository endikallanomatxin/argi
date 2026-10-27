const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/334X_implementation_operation_local_escape" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/334X_implementation_operation_local_escape", "local storage", "panic");
}
