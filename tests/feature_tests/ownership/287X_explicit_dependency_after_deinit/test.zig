const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/287X_explicit_dependency_after_deinit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/287X_explicit_dependency_after_deinit",
        "value depends on a root that has ended",
    );
}
