const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/173X_opaque_drop_all_still_blocks_root_end" {
    try buildExpectFail(
        "tests/feature_tests/ownership/173X_opaque_drop_all_still_blocks_root_end",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
