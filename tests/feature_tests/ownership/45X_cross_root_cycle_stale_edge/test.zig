const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/45X_cross_root_cycle_stale_edge" {
    try buildExpectFailExact("tests/feature_tests/ownership/45X_cross_root_cycle_stale_edge",
        \\tests/feature_tests/ownership/45X_cross_root_cycle_stale_edge/main.rg:18:18: error: reference depends on a root that has ended
        \\              if b.to_a&== 0 {
        \\                   ^
        \\
    );
}
