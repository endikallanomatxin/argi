const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/49X_structural_field_use_after_move" {
    try buildExpectFailExact("tests/feature_tests/ownership/49X_structural_field_use_after_move",
        \\tests/feature_tests/ownership/49X_structural_field_use_after_move/main.rg:13:24: error: place rooted at 'pair' is moved and cannot be used (moved at tests/feature_tests/ownership/49X_structural_field_use_after_move/main.rg:12:32)
        \\      status_code = pair.left + pair.right - moved
        \\                         ^
        \\
    );
}
