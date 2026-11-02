const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/05_assertion_failure" {
    try support.argiTestExpectStderrContains(
        "tests/feature_tests/testing/05_assertion_failure",
        &.{},
        1,
        "FAIL assertion_failure\n",
    );
}
