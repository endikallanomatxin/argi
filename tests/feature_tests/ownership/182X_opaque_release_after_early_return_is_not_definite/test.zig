const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/182X_opaque_release_after_early_return_is_not_definite" {
    try buildExpectFail(
        "tests/feature_tests/ownership/182X_opaque_release_after_early_return_is_not_definite",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
