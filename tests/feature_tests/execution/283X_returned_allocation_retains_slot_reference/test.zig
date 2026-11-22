const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "283X_returned_allocation_retains_slot_reference" {
    try support.expectFrontendFailure(
        "tests/feature_tests/execution/283X_returned_allocation_retains_slot_reference",
        "function output cannot depend on a local storage generation",
    );
}
