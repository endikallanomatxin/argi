const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/19_view_diagnostics view_mismatch" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/19_view_diagnostics", &.{ "--filter", "view_mismatch" }, 1, "views differ at index 1; lengths expected 3, actual 3");
}

test "feature_tests/testing/19_view_diagnostics byte_prefix" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/19_view_diagnostics", &.{ "--filter", "byte_prefix" }, 1, "bytes differ at byte 1: expected 2, actual <end>; lengths expected 2, actual 1");
}
