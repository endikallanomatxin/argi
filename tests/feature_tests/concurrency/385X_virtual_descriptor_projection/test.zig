const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "385X_virtual_descriptor_projection" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/385X_virtual_descriptor_projection", "Virtual descriptor storage is private");
}
