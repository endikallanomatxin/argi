const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/15_import_root_relative" {
    const test_path = "tests/feature_tests/modules/15_import_root_relative/project/app";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
