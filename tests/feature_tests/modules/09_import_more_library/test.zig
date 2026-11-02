const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/09_import_more_library" {
    const test_path = "tests/feature_tests/modules/09_import_more_library";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
