const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/116_partial_record_choice_payload" {
    try expectSuccessfulBuild("tests/feature_tests/execution/116_partial_record_choice_payload");
    try runExpect("tests/feature_tests/execution/116_partial_record_choice_payload", 42);
    try vmExpect("tests/feature_tests/execution/116_partial_record_choice_payload", 42, null);
}
