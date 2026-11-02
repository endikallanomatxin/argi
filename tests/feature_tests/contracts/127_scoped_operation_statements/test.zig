const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/127_scoped_operation_statements" {
    const path = "tests/feature_tests/contracts/127_scoped_operation_statements";
    try expectSuccessfulBuild(path);
    try run(path);
}
