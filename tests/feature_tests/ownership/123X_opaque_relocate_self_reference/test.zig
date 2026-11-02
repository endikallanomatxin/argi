const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/123X_opaque_relocate_self_reference" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/123X_opaque_relocate_self_reference",
        "opaque ownership storage cannot hide dependencies on external roots",
    );
}
