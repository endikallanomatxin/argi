const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/344X_open_operation_participant_ambiguity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/344X_open_operation_participant_ambiguity", "operation inputs do not determine a unique participant tuple", "without a diagnostic");
}
