const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/55X_deinit_through_alias_read" {
    try buildExpectFailExact("tests/feature_tests/ownership/55X_deinit_through_alias_read",
        \\tests/feature_tests/ownership/55X_deinit_through_alias_read/main.rg:12:16: error: reference depends on a root that has ended
        \\              if b&.size == 1 {
        \\                 ^
        \\
    );
}
