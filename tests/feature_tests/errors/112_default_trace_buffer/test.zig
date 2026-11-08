const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "default tracer buffers have independent caller storage" {
    const path = "tests/feature_tests/errors/112_default_trace_buffer";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
