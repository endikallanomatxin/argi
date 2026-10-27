const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/287X_conditional_storage_empty_repopulated" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/287X_conditional_storage_empty_repopulated", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
