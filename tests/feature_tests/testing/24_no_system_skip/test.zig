const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/24_no_system_skip" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/24_no_system_skip", &.{}, 0, "SKIP skips_without_system\n");
}
