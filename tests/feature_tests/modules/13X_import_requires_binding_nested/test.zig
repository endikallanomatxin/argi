const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/13X_import_requires_binding_nested" {
    try buildExpectFailExact("tests/feature_tests/modules/13X_import_requires_binding_nested",
        \\tests/feature_tests/modules/13X_import_requires_binding_nested/main.rg:3:9: error: import must be assigned to a name
        \\          import ("./dep")
        \\          ^
        \\
    );
}
