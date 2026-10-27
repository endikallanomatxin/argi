const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/16X_once_duplicate_direct" {
    try buildExpectFailExact("tests/feature_tests/system/16X_once_duplicate_direct",
        \\tests/feature_tests/system/16X_once_duplicate_direct/main.rg:6:5: error: once function 'setup' is consumed more than once from the reachable entrypoint graph (first use at tests/feature_tests/system/16X_once_duplicate_direct/main.rg:5:5 via 'main')
        \\      setup()
        \\      ^
        \\
    );
}
