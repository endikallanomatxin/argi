const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/43X_inferred_cleanup_ends_internal_root" {
    try buildExpectFailExact("tests/feature_tests/ownership/43X_inferred_cleanup_ends_internal_root",
        \\tests/feature_tests/ownership/43X_inferred_cleanup_ends_internal_root/main.rg:27:16: error: reference depends on a root that has ended
        \\              if alias&== 0 {
        \\                 ^
        \\
    );
}
