const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/22_optional_system" {
    try support.argiTestExpectStderr("tests/feature_tests/testing/22_optional_system", &.{}, 0, "PASS without_system\nPASS with_system\n");
}
