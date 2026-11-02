const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/25X_wrong_system_type" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/25X_wrong_system_type", &.{}, 1, "no function named 'wrong_system_type'");
}
