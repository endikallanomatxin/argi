const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/65X_projection_borrow_escape" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/65X_projection_borrow_escape", "function output cannot depend on a local storage generation that ends before return", "panic");
}
