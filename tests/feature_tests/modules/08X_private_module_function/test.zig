const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/08X_private_module_function" {
    try buildExpectFailExact("tests/feature_tests/modules/08X_private_module_function",
        \\tests/feature_tests/modules/08X_private_module_function/main.rg:3:37: error: function '_hidden_status' is private to its module
        \\      status_code = dep._hidden_status()
        \\                                      ^
        \\
    );
}
