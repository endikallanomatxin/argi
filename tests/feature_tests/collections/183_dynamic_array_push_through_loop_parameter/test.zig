const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/collections/183_dynamic_array_push_through_loop_parameter" {
    try support.expectSuccessfulBuild("tests/feature_tests/collections/183_dynamic_array_push_through_loop_parameter");
    try support.runExpectStdoutWithArgs("tests/feature_tests/collections/183_dynamic_array_push_through_loop_parameter", &.{}, 0, "");
}
