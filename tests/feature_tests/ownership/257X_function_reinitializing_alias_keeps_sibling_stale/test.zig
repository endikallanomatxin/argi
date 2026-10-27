const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/257X_function_reinitializing_alias_keeps_sibling_stale" {
    try buildExpectFail(
        "tests/feature_tests/ownership/257X_function_reinitializing_alias_keeps_sibling_stale",
        "reference depends on a root that has ended",
    );
}
