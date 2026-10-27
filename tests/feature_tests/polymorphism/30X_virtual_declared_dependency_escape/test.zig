const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/30X_virtual_declared_dependency_escape" {
    try expectFrontendFailure(
        "tests/feature_tests/polymorphism/30X_virtual_declared_dependency_escape",
        "function output cannot depend on a local storage generation that ends before return",
    );
}

test "tests/feature_tests/polymorphism/30X_virtual_declared_dependency_escape wrapper parity" {
    try support.expectSafetyWrapperParity("tests/feature_tests/polymorphism/30X_virtual_declared_dependency_escape", "function output cannot depend on a local storage generation that ends before return");
}
