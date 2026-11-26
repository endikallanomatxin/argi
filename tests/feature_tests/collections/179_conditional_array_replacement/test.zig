const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/179_conditional_array_replacement" {
    try expectSuccessfulBuild("tests/feature_tests/collections/179_conditional_array_replacement");
    try support.runExpectStdoutWithArgs("tests/feature_tests/collections/179_conditional_array_replacement", &.{}, 0, "");
    try support.runExpectStdoutWithArgs("tests/feature_tests/collections/179_conditional_array_replacement", &.{"replace"}, 0, "");
}
