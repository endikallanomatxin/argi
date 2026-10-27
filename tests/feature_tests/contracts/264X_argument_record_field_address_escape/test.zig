const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/264X_argument_record_field_address_escape" {
    try expectFrontendFailure("tests/feature_tests/contracts/264X_argument_record_field_address_escape", "function output cannot depend on a local storage generation");
}
