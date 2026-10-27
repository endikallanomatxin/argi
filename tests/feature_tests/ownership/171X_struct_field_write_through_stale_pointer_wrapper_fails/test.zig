const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/171X_struct_field_write_through_stale_pointer_wrapper_fails" {
    try buildExpectFail(
        "tests/feature_tests/ownership/171X_struct_field_write_through_stale_pointer_wrapper_fails",
        "reference depends on a root that has ended",
    );
}
