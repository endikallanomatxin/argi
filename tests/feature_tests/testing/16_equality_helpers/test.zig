const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/16_equality_helpers" {
    try support.argiTestExpectStderr("tests/feature_tests/testing/16_equality_helpers", &.{}, 0, "PASS equality_helpers\n");
}
