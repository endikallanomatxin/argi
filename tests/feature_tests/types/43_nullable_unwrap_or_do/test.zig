const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/43_nullable_unwrap_or_do" {
    const test_path = "tests/feature_tests/types/43_nullable_unwrap_or_do";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
