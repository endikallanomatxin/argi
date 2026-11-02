const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/08_struct_field_store" {
    const test_path = "tests/feature_tests/basics/08_struct_field_store";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
