const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/187_init_record_arguments" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/187_init_record_arguments");
    try run("tests/feature_tests/contracts/187_init_record_arguments");
}
