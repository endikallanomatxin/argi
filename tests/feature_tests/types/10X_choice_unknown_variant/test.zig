const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/10X_choice_unknown_variant" {
    try buildExpectFailExact("tests/feature_tests/types/10X_choice_unknown_variant",
        \\tests/feature_tests/types/10X_choice_unknown_variant/main.rg:7:24: error: choice type 'Direction' has no variant '..east'
        \\      value: Direction = ..east
        \\                         ^
        \\
    );
}
