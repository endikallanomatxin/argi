const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/19X_once_duplicate_branches" {
    try buildExpectFail(
        "tests/feature_tests/system/19X_once_duplicate_branches",
        "once function 'setup' is consumed more than once from the reachable entrypoint graph",
    );
}
