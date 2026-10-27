const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/38X_ambiguous_copy_struct_field" {
    try buildExpectFail("tests/feature_tests/ownership/38X_ambiguous_copy_struct_field", "cannot be copied implicitly");
}
