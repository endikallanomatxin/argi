const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/30X_tuple_borrow_dependency" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/30X_tuple_borrow_dependency", "undeclared output dependency", "panic");
}
