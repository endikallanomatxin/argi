const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/03X_import_missing_module" {
    try buildExpectFailExact("tests/feature_tests/modules/03X_import_missing_module",
        \\cannot resolve import './missing_dep' from 'tests/feature_tests/modules/03X_import_missing_module/main.rg'
        \\Build error: FileNotFound
        \\
    );
}
