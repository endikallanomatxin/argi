const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/01_simple_pass" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/01_simple_pass",
        &.{},
        0,
        "PASS simple_pass\n",
    );
}
