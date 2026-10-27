const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/149X_scoped_virtual_mutability" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/149X_scoped_virtual_mutability", "a mutable participant receiver requires a mutable concrete reference", "panic");
}
