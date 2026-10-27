const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/264X_argument_record_field_address_escape" {
    try buildExpectFail("tests/feature_tests/contracts/264X_argument_record_field_address_escape", "function output cannot depend on a local storage generation");
}
