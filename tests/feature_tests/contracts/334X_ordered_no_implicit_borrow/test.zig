const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/334X_ordered_no_implicit_borrow" {
    try buildExpectFail("tests/feature_tests/contracts/334X_ordered_no_implicit_borrow", "no conformance for the qualified operation's participants");
}
