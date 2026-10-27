const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/209X_deinit_virtual_receiver" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/209X_deinit_virtual_receiver", "consumes on an erased participant requires receiver cleanup identities");
}
