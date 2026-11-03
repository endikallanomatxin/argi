const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "associated constraints infer before dependent defaults" {
    const path = "tests/feature_tests/contracts/355_constraint_inference_before_defaults";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
