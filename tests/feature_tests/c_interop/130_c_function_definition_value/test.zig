const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/c_interop/130_c_function_definition_value" {
    const path = "tests/feature_tests/c_interop/130_c_function_definition_value";
    try expectSuccessfulBuild(path);
    try runExpect(path, 42);
}
