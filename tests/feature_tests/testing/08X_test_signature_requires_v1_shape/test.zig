const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/08X_test_signature_requires_v1_shape" {
    try support.argiTestExpectStderrContains(
        "tests/feature_tests/testing/08X_test_signature_requires_v1_shape",
        &.{},
        1,
        "tests accept no inputs or one '.system: System'",
    );
}
