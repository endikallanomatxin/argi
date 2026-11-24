const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "389X_joint_virtual_hidden_result" {
    const path = "tests/feature_tests/polymorphism/389X_joint_virtual_hidden_result";
    try support.expectFrontendFailure(path, "a hidden participant cannot appear in a virtual operation result");
}
