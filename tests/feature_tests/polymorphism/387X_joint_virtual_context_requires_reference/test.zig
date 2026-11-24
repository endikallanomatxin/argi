const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "387X_joint_virtual_context_requires_reference" {
    const path = "tests/feature_tests/polymorphism/387X_joint_virtual_context_requires_reference";
    try support.expectFrontendFailure(path, "joint Virtual context fields for contract participants must be references");
}
