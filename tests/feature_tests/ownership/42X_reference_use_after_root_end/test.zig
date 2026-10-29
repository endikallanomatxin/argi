const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/42X_reference_use_after_root_end" {
    try buildExpectFailExact("tests/feature_tests/ownership/42X_reference_use_after_root_end",
        \\tests/feature_tests/ownership/42X_reference_use_after_root_end/main.rg:16:16: error: reference depends on a root that has ended
        \\              if reference&== 0 {
        \\                 ^
        \\
    );
}
