const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/275X_specialized_ordering_missing" {
    try buildExpectFail("tests/feature_tests/types/275X_specialized_ordering_missing", "invalid conformance for contract 'CompareRelations': no conformance for the qualified operation's participants");
}
