const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/183X_opaque_write_after_release_repopulates_domain" {
    try buildExpectFail(
        "tests/feature_tests/ownership/183X_opaque_write_after_release_repopulates_domain",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
