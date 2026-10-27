const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/29X_assume_constructor_temporary_escape" {
    try buildExpectFail(
        "tests/feature_tests/functions/29X_assume_constructor_temporary_escape",
        "function output cannot depend on a local storage generation that ends before return",
    );
}
