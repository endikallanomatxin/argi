const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "388X_joint_virtual_reference_modes" {
    const path = "tests/feature_tests/polymorphism/388X_joint_virtual_reference_modes";
    try support.expectFrontendFailure(path, "the captured reference types have no selected conformance for this contract");
}
