const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/97_cancellation_deadline" {
    try expectSuccessfulBuild("tests/feature_tests/system/97_cancellation_deadline");
    try runExpect("tests/feature_tests/system/97_cancellation_deadline", 0);
}
