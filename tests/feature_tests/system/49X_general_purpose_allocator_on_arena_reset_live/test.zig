const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/49X_general_purpose_allocator_on_arena_reset_live" {
    try buildExpectFail(
        "tests/feature_tests/system/49X_general_purpose_allocator_on_arena_reset_live",
        "reference depends on a root that has ended",
    );
}
