const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/239_nested_contextual_record_layout" {
    try expectSuccessfulBuild("tests/feature_tests/execution/239_nested_contextual_record_layout");
    try runExpect("tests/feature_tests/execution/239_nested_contextual_record_layout", 42);
    try vmExpect("tests/feature_tests/execution/239_nested_contextual_record_layout", 42, null);
}
