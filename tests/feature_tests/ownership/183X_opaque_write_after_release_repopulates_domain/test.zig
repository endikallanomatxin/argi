const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/183X_opaque_write_after_release_repopulates_domain" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/183X_opaque_write_after_release_repopulates_domain",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
