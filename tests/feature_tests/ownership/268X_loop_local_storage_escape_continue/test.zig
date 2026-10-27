const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/268X_loop_local_storage_escape_continue" {
    try buildExpectFail(
        "tests/feature_tests/ownership/268X_loop_local_storage_escape_continue",
        "reference depends on a root that has ended",
    );
}
