const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/45X_c_allocator_missing_ffi" {
    try expectFrontendFailure("tests/feature_tests/system/45X_c_allocator_missing_ffi", "construction arguments cannot infer a matching Init target");
}
