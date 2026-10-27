const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/18X_once_duplicate_indirect" {
    try buildExpectFailExact("tests/feature_tests/system/18X_once_duplicate_indirect",
        \\tests/feature_tests/system/18X_once_duplicate_indirect/main.rg:9:5: error: once function 'setup' is consumed more than once from the reachable entrypoint graph (first use at tests/feature_tests/system/18X_once_duplicate_indirect/main.rg:5:5 via 'path_a')
        \\      setup()
        \\      ^
        \\
    );
}
