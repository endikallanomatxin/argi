const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "inline specialized function reflection and invocation" {
    const path = "tests/feature_tests/polymorphism/91_function_specialization_reflection";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
