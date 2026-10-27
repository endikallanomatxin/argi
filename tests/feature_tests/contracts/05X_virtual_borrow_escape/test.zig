const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/05X_virtual_borrow_escape" {
    try expectFrontendFailure("tests/feature_tests/contracts/05X_virtual_borrow_escape", "function output cannot depend on a local storage generation that ends before return");
}
