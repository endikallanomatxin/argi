const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/02_import_current_relative" {
    const test_path = "tests/feature_tests/modules/02_import_current_relative";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
