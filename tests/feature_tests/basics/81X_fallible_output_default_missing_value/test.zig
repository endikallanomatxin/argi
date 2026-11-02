const support = @import("../../../support.zig");
const expectSyntaxFailure = support.expectSyntaxFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/81X_fallible_output_default_missing_value" {
    try expectSyntaxFailure("tests/feature_tests/basics/81X_fallible_output_default_missing_value", "expected a default expression");
}
