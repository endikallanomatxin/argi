const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/06_direct_propagated_error" {
    try support.argiTestExpectStderrContains(
        "tests/feature_tests/testing/06_direct_propagated_error",
        &.{},
        1,
        "FAIL direct_propagation\n",
    );
}
