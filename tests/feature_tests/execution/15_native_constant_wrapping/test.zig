const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/15_native_constant_wrapping" {
    try support.expectSuccessfulBuild("tests/feature_tests/execution/15_native_constant_wrapping");
    try support.runExpect("tests/feature_tests/execution/15_native_constant_wrapping", 42);
    try support.expectArgiBuildSuccess(&.{ "build", "tests/feature_tests/execution/15_native_constant_wrapping", "--release" });
    try support.runExpect("tests/feature_tests/execution/15_native_constant_wrapping", 42);
}
