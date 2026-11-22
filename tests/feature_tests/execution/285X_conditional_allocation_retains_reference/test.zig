const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "285X_conditional_allocation_retains_reference" {
    try support.expectFrontendFailure(
        "tests/feature_tests/execution/285X_conditional_allocation_retains_reference",
        "function output cannot depend on a local storage generation",
    );
}
