const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/85X_semantic_relocation_double" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/85X_semantic_relocation_double",
        "binding 'source' was moved and cannot be used again",
    );
}
