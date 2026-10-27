const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/172X_nested_struct_field_write_precondition_keeps_projection" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/172X_nested_struct_field_write_precondition_keeps_projection",
        "reference depends on a root that has ended",
    );
}
