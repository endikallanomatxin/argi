const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/185X_opaque_release_in_one_branch_is_not_definite" {
    try buildExpectFail(
        "tests/feature_tests/ownership/185X_opaque_release_in_one_branch_is_not_definite",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
