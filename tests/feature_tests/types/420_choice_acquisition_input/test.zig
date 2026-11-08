const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "420_choice_acquisition_input" {
    const path = "tests/feature_tests/types/420_choice_acquisition_input";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
