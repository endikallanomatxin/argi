const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/05X_import_missing_overload" {
    try buildExpectFailExact("tests/feature_tests/modules/05X_import_missing_overload",
        \\tests/feature_tests/modules/05X_import_missing_overload/main.rg:3:35: error: module 'dep' has no function named 'missing_func'
        \\      status_code = dep.missing_func()
        \\                                    ^
        \\
    );
}
