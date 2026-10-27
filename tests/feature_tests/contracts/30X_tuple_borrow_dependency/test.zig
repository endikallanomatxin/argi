const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/30X_tuple_borrow_dependency" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/30X_tuple_borrow_dependency", "undeclared output dependency", "panic");
}
