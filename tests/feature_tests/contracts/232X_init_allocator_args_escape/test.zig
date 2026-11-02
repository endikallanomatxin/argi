const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/232X_init_allocator_args_escape" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/232X_init_allocator_args_escape", "local storage generation");
}
