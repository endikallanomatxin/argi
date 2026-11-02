const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/21_modern_test_syntax" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/21_modern_test_syntax",
        &.{},
        0,
        "PASS modern\nPASS multiline\nPASS explicit\n",
    );
}
