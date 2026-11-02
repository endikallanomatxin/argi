const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/31X_reference_to_constructor_temporary_escape" {
    try expectFrontendFailure(
        "tests/feature_tests/functions/31X_reference_to_constructor_temporary_escape",
        "function output cannot depend on a local storage generation that ends before return",
    );
}
