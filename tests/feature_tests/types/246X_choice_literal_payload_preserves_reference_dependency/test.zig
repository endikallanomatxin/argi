const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/246X_choice_literal_payload_preserves_reference_dependency" {
    try buildExpectFail(
        "tests/feature_tests/types/246X_choice_literal_payload_preserves_reference_dependency",
        "reference depends on a root that has ended",
    );
}
