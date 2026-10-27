const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/03_duration" {
    const path = "tests/feature_tests/numbers/03_duration";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
