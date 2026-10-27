const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/59X_branch_deinit_then_use" {
    try buildExpectFailExact("tests/feature_tests/ownership/59X_branch_deinit_then_use",
        \\tests/feature_tests/ownership/59X_branch_deinit_then_use/main.rg:13:27: error: place rooted at 'allocation' is maybe_initialized and cannot be used
        \\              if allocation.size == 1 {
        \\                            ^
        \\
    );
}

test "tests/feature_tests/ownership/59X_branch_deinit_then_use wrapper parity" {
    try support.expectSafetyWrapperParity("tests/feature_tests/ownership/59X_branch_deinit_then_use", "maybe_initialized and cannot be used");
}
