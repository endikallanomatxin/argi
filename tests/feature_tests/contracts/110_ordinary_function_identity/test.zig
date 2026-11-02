const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/110_ordinary_function_identity" {
    const path = "tests/feature_tests/contracts/110_ordinary_function_identity";
    try expectSuccessfulBuild(path);
    try run(path);
}
