const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/113_error_tracer_borrowed_buffer" {
    const path = "tests/feature_tests/types/113_error_tracer_borrowed_buffer";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
