const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/65X_projection_borrow_escape" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/65X_projection_borrow_escape", "function output cannot depend on a local storage generation that ends before return", "panic");
}
