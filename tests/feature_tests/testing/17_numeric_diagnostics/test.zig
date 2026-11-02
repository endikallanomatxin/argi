const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/17_numeric_diagnostics signed_value" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/17_numeric_diagnostics", &.{ "--filter", "signed_value" }, 1, "expected -9223372036854775808, actual 9223372036854775807");
}

test "feature_tests/testing/17_numeric_diagnostics unsigned_value" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/17_numeric_diagnostics", &.{ "--filter", "unsigned_value" }, 1, "expected 18446744073709551615, actual 0");
}

test "feature_tests/testing/17_numeric_diagnostics float_value" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/17_numeric_diagnostics", &.{ "--filter", "float_value" }, 1, "expected 1.5, actual 2.5");
}

test "feature_tests/testing/17_numeric_diagnostics bool_value" {
    try support.argiTestExpectStderrContains("tests/feature_tests/testing/17_numeric_diagnostics", &.{ "--filter", "bool_value" }, 1, "expected true, actual false");
}
