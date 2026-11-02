const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/18_string_diagnostics string_mismatch" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/18_string_diagnostics", &.{ "--filter", "string_mismatch" }, 1, "strings differ at byte 1: expected 98, actual 120; lengths expected 3, actual 3");
}

test "feature_tests/testing/18_string_diagnostics string_prefix" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/18_string_diagnostics", &.{ "--filter", "string_prefix" }, 1, "strings differ at byte 2: expected 99, actual <end>; lengths expected 3, actual 2");
}

test "feature_tests/testing/18_string_diagnostics string_empty" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/18_string_diagnostics", &.{ "--filter", "string_empty" }, 1, "strings differ at byte 0: expected <end>, actual 120; lengths expected 0, actual 1");
}

test "feature_tests/testing/18_string_diagnostics string_embedded_nul" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/18_string_diagnostics", &.{ "--filter", "string_embedded_nul" }, 1, "strings differ at byte 2: expected 90, actual 91; lengths expected 3, actual 3");
}
