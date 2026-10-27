const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/45X_c_allocator_missing_ffi" {
    try buildExpectFail("tests/feature_tests/system/45X_c_allocator_missing_ffi", "ffi");
}
