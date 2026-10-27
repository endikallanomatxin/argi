const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/16X_integer_division_zero" {
    try support.expectSuccessfulBuild("tests/feature_tests/execution/16X_integer_division_zero");
    try support.runExpectFailure("tests/feature_tests/execution/16X_integer_division_zero");
    try support.expectArgiBuildSuccess(&.{ "build", "tests/feature_tests/execution/16X_integer_division_zero", "--release" });
    try support.runExpectFailure("tests/feature_tests/execution/16X_integer_division_zero");
    try support.vmExpect("tests/feature_tests/execution/16X_integer_division_zero", 1, "ExecutionDivisionByZero");
}
