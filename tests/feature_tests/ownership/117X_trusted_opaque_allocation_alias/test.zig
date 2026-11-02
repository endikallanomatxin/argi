const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/117X_trusted_opaque_allocation_alias" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/117X_trusted_opaque_allocation_alias",
        "opaque ownership storage requires no live external aliases to the consumed root",
    );
}
