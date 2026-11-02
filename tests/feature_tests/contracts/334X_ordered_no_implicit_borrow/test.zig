const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/334X_ordered_no_implicit_borrow" {
    try expectFrontendFailure("tests/feature_tests/contracts/334X_ordered_no_implicit_borrow", "no conformance for the qualified operation's participants");
}
