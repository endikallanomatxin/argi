const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/10_expected_error_mismatch" {
    try support.argiTestExpectStderrContains(
        "tests/feature_tests/testing/10_expected_error_mismatch",
        &.{},
        1,
        "FAIL expected_error_mismatch\n",
    );
}
