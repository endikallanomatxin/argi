const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/06X_private_module_value" {
    try buildExpectFailExact("tests/feature_tests/modules/06X_private_module_value",
        \\tests/feature_tests/modules/06X_private_module_value/main.rg:3:19: error: value '_hidden_value' is private to its module
        \\      status_code = dep._hidden_value
        \\                    ^
        \\
    );
}
