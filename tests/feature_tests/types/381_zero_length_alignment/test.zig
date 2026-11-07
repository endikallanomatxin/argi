const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "zero length arrays preserve element alignment without constructing elements" {
    const path = "tests/feature_tests/types/381_zero_length_alignment";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
