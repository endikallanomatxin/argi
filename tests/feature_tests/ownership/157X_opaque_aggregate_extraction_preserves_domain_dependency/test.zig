const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/157X_opaque_aggregate_extraction_preserves_domain_dependency" {
    try buildExpectFail(
        "tests/feature_tests/ownership/157X_opaque_aggregate_extraction_preserves_domain_dependency",
        "reference depends on a root that has ended",
    );
}
