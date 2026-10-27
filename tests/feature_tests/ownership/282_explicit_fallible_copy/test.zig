const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/282_explicit_fallible_copy" {
    const test_path = "tests/feature_tests/ownership/282_explicit_fallible_copy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
