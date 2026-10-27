const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/175X_opaque_release_one_domain_keeps_other_hidden" {
    try buildExpectFail(
        "tests/feature_tests/ownership/175X_opaque_release_one_domain_keeps_other_hidden",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
