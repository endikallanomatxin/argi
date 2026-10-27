const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/12X_import_requires_binding" {
    try buildExpectFailExact("tests/feature_tests/modules/12X_import_requires_binding",
        \\tests/feature_tests/modules/12X_import_requires_binding/main.rg:1:1: error: import must be assigned to a name
        \\  import ("./dep")
        \\  ^
        \\
    );
}
