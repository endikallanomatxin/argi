const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/431X_allocation_cleanup_provider_replacement" {
    try expectFrontendFailure("tests/feature_tests/types/431X_allocation_cleanup_provider_replacement", "field '_deallocator' is private to its module");
}
