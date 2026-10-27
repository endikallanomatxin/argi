const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/71X_virtual_pipe_temporary_escape" {
    try buildExpectFail("tests/feature_tests/types/71X_virtual_pipe_temporary_escape", "local storage generation");
}
