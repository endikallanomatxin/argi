const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/66X_allocation_stateful_allocator_escape" {
    try expectFrontendFailure("tests/feature_tests/ownership/66X_allocation_stateful_allocator_escape", "local storage generation");
}
