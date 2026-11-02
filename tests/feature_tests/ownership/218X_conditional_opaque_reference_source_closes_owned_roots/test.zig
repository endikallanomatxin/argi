const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/218X_conditional_opaque_reference_source_closes_owned_roots" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/218X_conditional_opaque_reference_source_closes_owned_roots",
        "opaque ownership storage requires no live external aliases to the consumed root",
    );
}
