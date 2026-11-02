const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/testing/33_module_local_discovery" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/33_module_local_discovery",
        &.{},
        0,
        "PASS local\nPASS shared_name\nPASS sibling\n",
    );
}

test "feature_tests/testing/33_module_local_discovery filters only local declarations" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/33_module_local_discovery",
        &.{ "--filter", "dependency_only" },
        1,
        "No tests found\n",
    );
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/33_module_local_discovery",
        &.{ "--filter", "shared_name" },
        0,
        "PASS shared_name\n",
    );
}

test "feature_tests/testing/33_module_local_discovery imported tests do not populate an empty module" {
    try support.argiTestExpectStderr(
        "tests/feature_tests/testing/33_module_local_discovery/without_tests",
        &.{},
        1,
        "No tests found\n",
    );
}
