const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/03_once_isolated_per_test" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/03_once_isolated_per_test",
        &.{},
        0,
        "PASS first\nPASS second\n",
    );
}

test "feature_tests/testing/03_once_isolated_per_test_filter" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/03_once_isolated_per_test",
        &.{ "--filter", "second" },
        0,
        "PASS second\n",
    );
}
