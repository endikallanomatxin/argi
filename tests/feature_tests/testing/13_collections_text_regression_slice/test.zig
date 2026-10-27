const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/13_collections_text_regression_slice" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/13_collections_text_regression_slice",
        &.{},
        0,
        "PASS collections_text_array_slice\nPASS collections_text_format_slice\n",
    );
}
