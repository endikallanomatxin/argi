const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/115_inline_operation_bodies" {
    const path = "tests/feature_tests/contracts/115_inline_operation_bodies";
    try expectSuccessfulBuild(path);
    try run(path);
}
