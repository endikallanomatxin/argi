const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/47X_page_allocator_missing_memory" {
    try expectFrontendFailure("tests/feature_tests/system/47X_page_allocator_missing_memory", "construction arguments cannot infer a matching Init target");
}
