const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/77_computed_test_condition" {
    try support.argiTestExpectStderr("tests/feature_tests/execution/77_computed_test_condition", &.{}, 0, "PASS selected\n");
}
