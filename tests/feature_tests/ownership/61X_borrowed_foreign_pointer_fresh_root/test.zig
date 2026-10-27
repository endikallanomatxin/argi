const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/61X_borrowed_foreign_pointer_fresh_root" {
    try buildExpectFail("tests/feature_tests/ownership/61X_borrowed_foreign_pointer_fresh_root", "no function named 'establish_fresh_reference' exists");
}
