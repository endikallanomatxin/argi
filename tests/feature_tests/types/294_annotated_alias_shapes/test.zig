const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/294_annotated_alias_shapes" {
    try expectSuccessfulBuild("tests/feature_tests/types/294_annotated_alias_shapes");
    try run("tests/feature_tests/types/294_annotated_alias_shapes");
    try support.vmExpect("tests/feature_tests/types/294_annotated_alias_shapes", 0, null);
}
