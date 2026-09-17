from pathlib import Path

# The currently verified source edits have landed. Keep the remote edit harness
# idle until the next parity change while retaining a focused smoke baseline.
Path(".git/semantic-refactor-message").write_text("No semantic source edit")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/collections/09_dynamic_array_ergonomic "
    "-Dtest-filter=feature_tests/collections/18_dynamic_array_copy "
    "-Dtest-filter=feature_tests/control_flow/04_for_dynamic_array "
    "-Dtest-filter=feature_tests/control_flow/14_for_mut_borrowed_dynamic_array\n"
)
