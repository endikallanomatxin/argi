const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/116_inline_no_associated" {
    const path = "tests/feature_tests/contracts/116_inline_no_associated";
    try expectSuccessfulBuild(path);
    try run(path);
}
