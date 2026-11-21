const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "a conditional array load retains every possible reference dependency" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/314X_conditional_array_load_retains_reference", "reference depends on a root that has ended");
}
