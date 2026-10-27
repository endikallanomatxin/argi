const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/11X_import_cycle" {
    try buildExpectFailExact("tests/feature_tests/modules/11X_import_cycle",
        \\import cycle detected: tests/feature_tests/modules/11X_import_cycle/dep_a -> tests/feature_tests/modules/11X_import_cycle/dep_b -> tests/feature_tests/modules/11X_import_cycle/dep_a
        \\Build error: ImportCycle
        \\
    );
}
