const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/25X_dynamic_array_owning_push_moves_source" {
    try buildExpectFail(
        "tests/feature_tests/collections/25X_dynamic_array_owning_push_moves_source",
        "binding 'value' was moved and cannot be used again",
    );
}
