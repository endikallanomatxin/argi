const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/78X_computed_discarded_binding" {
    try buildExpectFail("tests/feature_tests/execution/78X_computed_discarded_binding", "unknown name 'missing' in this scope");
}
