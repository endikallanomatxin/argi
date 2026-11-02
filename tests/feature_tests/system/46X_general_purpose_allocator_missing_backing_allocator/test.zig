const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/46X_general_purpose_allocator_missing_backing_allocator" {
    try expectFrontendFailure("tests/feature_tests/system/46X_general_purpose_allocator_missing_backing_allocator", "construction arguments cannot infer a matching Init target");
}
