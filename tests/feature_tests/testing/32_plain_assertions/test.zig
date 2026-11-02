const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/32_plain_assertions" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/32_plain_assertions",
        &.{ "--filter", "plain_assertions" },
        0,
        "PASS plain_assertions\n",
    );
    try support.argiTestExpectStderrContains(
        "tests/feature_tests/testing/32_plain_assertions",
        &.{ "--filter", "plain_failure" },
        1,
        "FAIL plain_failure\n",
    );
    try support.argiTestExpectStderrContains(
        "tests/feature_tests/testing/32_plain_assertions",
        &.{ "--filter", "plain_skip" },
        0,
        "SKIP plain_skip\n",
    );
}
