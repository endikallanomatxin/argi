const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/54X_virtual_bound_borrow_after_cleanup" {
    try buildExpectFail("tests/feature_tests/polymorphism/54X_virtual_bound_borrow_after_cleanup", "root that has ended");
}
