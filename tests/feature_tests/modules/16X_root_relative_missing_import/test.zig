const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/16X_root_relative_missing_import" {
    try buildExpectFailExact("tests/feature_tests/modules/16X_root_relative_missing_import/project/app",
        \\cannot resolve import '.../missing_shared' from 'tests/feature_tests/modules/16X_root_relative_missing_import/project/app/main.rg'
        \\Build error: FileNotFound
        \\
    );
}
