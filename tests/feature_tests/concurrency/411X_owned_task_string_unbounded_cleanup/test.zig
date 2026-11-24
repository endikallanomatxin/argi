const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "411X_owned_task_string_unbounded_cleanup" {
    try support.expectFrontendDiagnostic("tests/feature_tests/concurrency/411X_owned_task_string_unbounded_cleanup", .{
        .origin = .bundled_core,
        .message = "isolated callback cannot access a virtual operation without a checked cross-execution guarantee",
        .forbidden = &.{"isolated callback cannot access foreign or unresolved functions"},
    });
}
