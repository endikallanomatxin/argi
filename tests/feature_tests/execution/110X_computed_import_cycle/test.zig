const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/110X_computed_import_cycle" {
    try buildExpectFail("tests/feature_tests/execution/110X_computed_import_cycle", "import cycle detected after compile-time selection");
}
