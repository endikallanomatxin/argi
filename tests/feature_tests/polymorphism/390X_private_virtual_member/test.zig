const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "390X_private_virtual_member" {
    const path = "tests/feature_tests/polymorphism/390X_private_virtual_member";
    try support.expectFrontendFailure(path, "contract operation is private to its defining module");
}
