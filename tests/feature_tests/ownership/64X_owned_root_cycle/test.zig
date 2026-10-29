const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/64X_owned_root_cycle" {
    try buildExpectFailExact("tests/feature_tests/ownership/64X_owned_root_cycle",
        \\tests/feature_tests/ownership/64X_owned_root_cycle/main.rg:36:21: error: root ownership must be acyclic
        \\                      slot_b&= ~a
        \\                      ^
        \\
    );
}
