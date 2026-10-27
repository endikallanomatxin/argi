const support = @import("../../../support.zig");
const expectFrontendDiagnostic = support.expectFrontendDiagnostic;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/161X_standard_hash_requires_equality" {
    try expectFrontendDiagnostic("tests/feature_tests/collections/161X_standard_hash_requires_equality", .{ .message = "a required contract dependency is not satisfied", .origin = .bundled_core });
}
