const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/31_computed_module_selection" {
    try support.argiTestExpectStderr("tests/feature_tests/testing/31_computed_module_selection", &.{}, 0, "PASS selected\n");
    try support.argiTestExpectStderr("tests/feature_tests/testing/31_computed_module_selection", &.{ "--filter", "discarded" }, 1, "No tests found\n");
}
