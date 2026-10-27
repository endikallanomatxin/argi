const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/109X_collection_reverse_owning" {
    try buildExpectFail("tests/feature_tests/collections/109X_collection_reverse_owning", "contract constraint 'ImplicitlyCopyable' required by generic function parameter '.t' of 'reverse'");
}
