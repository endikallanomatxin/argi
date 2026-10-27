const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/15_named_optional_view_return" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/15_named_optional_view_return",
        &.{},
        0,
        "PASS named_optional_view_return\n",
    );
}
