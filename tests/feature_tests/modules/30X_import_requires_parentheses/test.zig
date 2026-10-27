const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/30X_import_requires_parentheses" {
    try buildExpectFail("tests/feature_tests/modules/30X_import_requires_parentheses", "expected '(' after import");
}
