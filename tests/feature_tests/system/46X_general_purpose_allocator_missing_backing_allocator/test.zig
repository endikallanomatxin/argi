const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/46X_general_purpose_allocator_missing_backing_allocator" {
    try buildExpectFail("tests/feature_tests/system/46X_general_purpose_allocator_missing_backing_allocator", "allocator");
}
