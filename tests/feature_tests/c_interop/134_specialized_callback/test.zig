const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "specialized C function definition as callback" {
    const path = "tests/feature_tests/c_interop/134_specialized_callback";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 42);
}
