const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/267X_loop_local_storage_escape_break" {
    try buildExpectFail(
        "tests/feature_tests/ownership/267X_loop_local_storage_escape_break",
        "reference depends on a root that has ended",
    );
}
