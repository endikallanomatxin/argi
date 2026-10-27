const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/254X_reinitializing_alias_does_not_refresh_sibling" {
    try buildExpectFail(
        "tests/feature_tests/ownership/254X_reinitializing_alias_does_not_refresh_sibling",
        "reference depends on a root that has ended",
    );
}
