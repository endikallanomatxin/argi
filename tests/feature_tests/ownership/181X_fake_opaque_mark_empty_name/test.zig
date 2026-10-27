const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/181X_fake_opaque_mark_empty_name" {
    try buildExpectFail(
        "tests/feature_tests/ownership/181X_fake_opaque_mark_empty_name",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
