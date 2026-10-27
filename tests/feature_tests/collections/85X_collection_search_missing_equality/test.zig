const support = @import("../../../support.zig");
const expectFrontendDiagnostic = support.expectFrontendDiagnostic;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/85X_collection_search_missing_equality" {
    try expectFrontendDiagnostic("tests/feature_tests/collections/85X_collection_search_missing_equality", .{ .message = "no conformance for the qualified operation's participants", .origin = .bundled_core });
}
