const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/14_integer_boundaries_vm" {
    try support.expectSuccessfulBuild("tests/feature_tests/execution/14_integer_boundaries_vm");
    try support.runExpect("tests/feature_tests/execution/14_integer_boundaries_vm", 42);
    try support.expectArgiBuildSuccess(&.{ "build", "tests/feature_tests/execution/14_integer_boundaries_vm", "--release" });
    try support.runExpect("tests/feature_tests/execution/14_integer_boundaries_vm", 42);
    try support.vmExpect("tests/feature_tests/execution/14_integer_boundaries_vm", 42, null);
}
