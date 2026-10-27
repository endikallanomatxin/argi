const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/16X_function_signature_requires_explicit_types" {
    try buildExpectFailExact("tests/feature_tests/functions/16X_function_signature_requires_explicit_types",
        \\tests/feature_tests/functions/16X_function_signature_requires_explicit_types/main.rg:1:34: error: function output field '.result' requires an explicit type
        \\  identity := (.value: Int32) -> (.result) {
        \\                                   ^
        \\
    );
}
