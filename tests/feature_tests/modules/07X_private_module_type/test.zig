const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/07X_private_module_type" {
    try buildExpectFailExact("tests/feature_tests/modules/07X_private_module_type",
        \\tests/feature_tests/modules/07X_private_module_type/main.rg:3:13: error: type '_HiddenStatus' is private to its module
        \\      hidden: dep._HiddenStatus = (.code = 0)
        \\              ^
        \\
    );
}
