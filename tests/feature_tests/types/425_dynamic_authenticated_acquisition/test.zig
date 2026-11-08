const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "425_dynamic_authenticated_acquisition" {
    const path = "tests/feature_tests/types/425_dynamic_authenticated_acquisition";
    try support.expectSuccessfulBuild(path);
}
