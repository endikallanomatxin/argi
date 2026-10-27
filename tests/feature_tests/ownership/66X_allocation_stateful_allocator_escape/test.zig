const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/66X_allocation_stateful_allocator_escape" {
    try buildExpectFail("tests/feature_tests/ownership/66X_allocation_stateful_allocator_escape", "local storage generation");
}
