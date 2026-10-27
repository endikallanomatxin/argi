const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/02_skip" {
    try support.argiTestExpectStderrContains(
        "tests/feature_tests/testing/02_skip",
        &.{},
        0,
        "SKIP skipped_case\n",
    );
}
