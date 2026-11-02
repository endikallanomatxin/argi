const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/12_language_regression_slice" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/12_language_regression_slice",
        &.{},
        0,
        "PASS language_regression_slice\n",
    );
}
