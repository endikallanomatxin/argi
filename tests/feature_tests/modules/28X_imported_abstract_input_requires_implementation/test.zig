const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/modules/28X_imported_abstract_input_requires_implementation" {
    try expectFrontendFailure(
        "tests/feature_tests/modules/28X_imported_abstract_input_requires_implementation",
        "contract constraint 'ExampleAbstract' required by generic function parameter '.Value' of 'use_value'",
    );
}
