const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/33X_static_abstract_generic_field_requires_implementation" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/33X_static_abstract_generic_field_requires_implementation",
        "does not implement contract 'Backend' required by generic type parameter '.backend_type' of 'Wrapper'",
    );
}
