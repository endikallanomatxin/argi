const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/34X_static_abstract_generic_field_identity" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/34X_static_abstract_generic_field_identity",
        "no function named 'accept_b' accepts arguments (.value: Wrapper#(.backend_type: BackendA))",
    );
}
