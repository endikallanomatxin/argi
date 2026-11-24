const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "386X_virtual_hidden_associated_type" {
    const path = "tests/feature_tests/polymorphism/386X_virtual_hidden_associated_type";
    try support.expectFrontendFailure(path, "the hidden participant cannot appear in a virtual operation result");
}
