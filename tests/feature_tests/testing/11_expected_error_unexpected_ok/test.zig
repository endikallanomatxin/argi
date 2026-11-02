const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/11_expected_error_unexpected_ok" {
    try support.argiTestExpectStderrContains(
        "tests/feature_tests/testing/11_expected_error_unexpected_ok",
        &.{},
        1,
        "FAIL expected_error_unexpected_ok\n",
    );
}
