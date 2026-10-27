const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/168X_nested_pointer_use_precondition_keeps_projection" {
    try buildExpectFail(
        "tests/feature_tests/ownership/168X_nested_pointer_use_precondition_keeps_projection",
        "reference depends on a root that has ended",
    );
}
