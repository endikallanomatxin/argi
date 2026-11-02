const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/04X_import_missing_value" {
    try buildExpectFailExact("tests/feature_tests/modules/04X_import_missing_value",
        \\tests/feature_tests/modules/04X_import_missing_value/main.rg:3:19: error: module 'dep' has no value '.missing_value'
        \\      status_code = dep.missing_value
        \\                    ^
        \\
    );
}
