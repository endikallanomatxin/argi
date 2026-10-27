const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/14X_missing_function_name" {
    try buildExpectFailExact("tests/feature_tests/modules/14X_missing_function_name",
        \\tests/feature_tests/modules/14X_missing_function_name/main.rg:2:31: error: no function named 'missing_func' exists
        \\      status_code = missing_func()
        \\                                ^
        \\
    );
}
