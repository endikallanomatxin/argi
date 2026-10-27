const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/301X_opaque_scalar_borrow_element_moved" {
    try buildExpectFail("tests/feature_tests/ownership/301X_opaque_scalar_borrow_element_moved", "place rooted at 'element' is moved and cannot be used");
}
