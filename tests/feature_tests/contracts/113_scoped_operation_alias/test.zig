const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/113_scoped_operation_alias" {
    const path = "tests/feature_tests/contracts/113_scoped_operation_alias";
    try expectSuccessfulBuild(path);
    try run(path);
}
