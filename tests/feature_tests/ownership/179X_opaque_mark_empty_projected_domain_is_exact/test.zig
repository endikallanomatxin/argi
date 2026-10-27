const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/179X_opaque_mark_empty_projected_domain_is_exact" {
    try buildExpectFail(
        "tests/feature_tests/ownership/179X_opaque_mark_empty_projected_domain_is_exact",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
