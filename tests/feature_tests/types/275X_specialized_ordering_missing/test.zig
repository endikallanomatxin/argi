const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/275X_specialized_ordering_missing" {
    try expectFrontendFailure("tests/feature_tests/types/275X_specialized_ordering_missing", "invalid conformance for contract 'CompareRelations': no conformance for the qualified operation's participants");
}
