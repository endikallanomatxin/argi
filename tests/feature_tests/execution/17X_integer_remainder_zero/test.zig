const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/17X_integer_remainder_zero" {
    try support.expectSuccessfulBuild("tests/feature_tests/execution/17X_integer_remainder_zero");
    try support.runExpectFailure("tests/feature_tests/execution/17X_integer_remainder_zero");
    try support.expectArgiBuildSuccess(&.{ "build", "tests/feature_tests/execution/17X_integer_remainder_zero", "--release" });
    try support.runExpectFailure("tests/feature_tests/execution/17X_integer_remainder_zero");
    try support.vmExpect("tests/feature_tests/execution/17X_integer_remainder_zero", 1, "ExecutionDivisionByZero");
}
