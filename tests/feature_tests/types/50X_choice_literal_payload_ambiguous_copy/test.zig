const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/50X_choice_literal_payload_ambiguous_copy" {
    try buildExpectFail("tests/feature_tests/types/50X_choice_literal_payload_ambiguous_copy", "cannot be copied implicitly");
}
