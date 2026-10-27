const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/23_no_system_failure" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/23_no_system_failure", &.{}, 1, "FAIL fails_without_system\n");
}
