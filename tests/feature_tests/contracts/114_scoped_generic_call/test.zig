const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/114_scoped_generic_call" {
    const path = "tests/feature_tests/contracts/114_scoped_generic_call";
    try expectSuccessfulBuild(path);
    try run(path);
}
