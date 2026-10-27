const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/66X_contextual_choice_ambiguous" {
    try buildExpectFail("tests/feature_tests/polymorphism/66X_contextual_choice_ambiguous", "multiple applicable operation identities");
}
