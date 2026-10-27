const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/20_bounded_diagnostics bounded_message" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/20_bounded_diagnostics", &.{ "--filter", "bounded_message" }, 1, "<context truncated>");
}
