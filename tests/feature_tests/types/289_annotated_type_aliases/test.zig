const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/289_annotated_type_aliases" {
    try expectSuccessfulBuild("tests/feature_tests/types/289_annotated_type_aliases");
    try run("tests/feature_tests/types/289_annotated_type_aliases");
}
