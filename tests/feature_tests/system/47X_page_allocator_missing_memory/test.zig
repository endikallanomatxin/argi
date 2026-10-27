const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/47X_page_allocator_missing_memory" {
    try buildExpectFail("tests/feature_tests/system/47X_page_allocator_missing_memory", "memory");
}
