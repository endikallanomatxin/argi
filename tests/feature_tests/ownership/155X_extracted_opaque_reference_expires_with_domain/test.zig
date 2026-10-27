const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/155X_extracted_opaque_reference_expires_with_domain" {
    try buildExpectFail(
        "tests/feature_tests/ownership/155X_extracted_opaque_reference_expires_with_domain",
        "reference depends on a root that has ended",
    );
}
