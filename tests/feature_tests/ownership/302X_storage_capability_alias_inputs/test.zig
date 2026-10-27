const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/302X_storage_capability_alias_inputs" {
    try buildExpectFail("tests/feature_tests/ownership/302X_storage_capability_alias_inputs", "more than once");
}
