const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "compile-time conditions retain function definition captures" {
    const path = "tests/feature_tests/polymorphism/97_comptime_function_condition";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
