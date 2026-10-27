const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/09_expected_error" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/09_expected_error",
        &.{},
        0,
        "PASS expected_error\n",
    );
}
