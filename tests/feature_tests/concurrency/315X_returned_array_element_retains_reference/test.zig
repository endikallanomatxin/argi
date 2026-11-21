const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "a returned array element retains the dependencies of its stored value" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/315X_returned_array_element_retains_reference", "reference depends on a root that has ended");
}
