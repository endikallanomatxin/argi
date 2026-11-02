const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/04_expect_equal" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/04_expect_equal",
        &.{},
        0,
        "PASS equality\n",
    );
}
