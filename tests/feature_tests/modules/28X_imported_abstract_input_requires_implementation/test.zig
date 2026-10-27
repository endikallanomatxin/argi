const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/28X_imported_abstract_input_requires_implementation" {
    try buildExpectFail(
        "tests/feature_tests/modules/28X_imported_abstract_input_requires_implementation",
        "contract constraint 'ExampleAbstract' required by generic function parameter '.Value' of 'use_value'",
    );
}
