const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/310X_storage_capability_reference_input" {
    try buildExpectFail("tests/feature_tests/ownership/310X_storage_capability_reference_input", "already been consumed");
}
