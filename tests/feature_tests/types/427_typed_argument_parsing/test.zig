const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/427_typed_argument_parsing" {
    const path = "tests/feature_tests/types/427_typed_argument_parsing";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
