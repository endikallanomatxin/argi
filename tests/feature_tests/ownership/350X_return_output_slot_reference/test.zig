const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/350X_return_output_slot_reference" {
    try buildExpectFail("tests/feature_tests/ownership/350X_return_output_slot_reference", "local storage generation");
}
