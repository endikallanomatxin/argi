const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "packed input cannot be consumed twice" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/84X_packed_function_lifetime", "binding 'args' was moved and cannot be used again");
}
