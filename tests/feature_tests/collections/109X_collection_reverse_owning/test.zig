const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/109X_collection_reverse_owning" {
    try expectFrontendFailure("tests/feature_tests/collections/109X_collection_reverse_owning", "contract constraint 'ImplicitlyCopyable' required by generic function parameter '.t' of 'reverse'");
}
