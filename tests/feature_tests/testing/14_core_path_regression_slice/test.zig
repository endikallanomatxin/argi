const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/14_core_path_regression_slice" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/14_core_path_regression_slice",
        &.{},
        0,
        "PASS core_path_regression_slice\n",
    );
}
