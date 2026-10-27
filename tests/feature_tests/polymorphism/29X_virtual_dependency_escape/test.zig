const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/29X_virtual_dependency_escape" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/29X_virtual_dependency_escape",
        "function output cannot depend on a local storage generation that ends before return",
    );
}
