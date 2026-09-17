from pathlib import Path

# The previous semantic edit is now committed. Disable the post-edit patch in
# the runner and use this harness revision only to measure the next regression
# cluster without changing source.
Path(".github/semantic_refactor_post_edit.py").write_text("# no-op measurement run\n")
Path(".git/semantic-refactor-message").write_text("Measure DynamicArray regressions")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/control_flow/04_for_dynamic_array "
    "-Dtest-filter=feature_tests/control_flow/14_for_mut_borrowed_dynamic_array "
    "-Dtest-filter=feature_tests/collections/08_dynamic_array "
    "-Dtest-filter=feature_tests/collections/09_dynamic_array_ergonomic "
    "-Dtest-filter=feature_tests/collections/16_dynamic_array_iterator_manual "
    "-Dtest-filter=feature_tests/collections/18_dynamic_array_copy "
    "-Dtest-filter=feature_tests/collections/19_dynamic_array_borrowed_index_read_only "
    "-Dtest-filter=feature_tests/collections/20_dynamic_array_borrowed_index_mutable "
    "-Dtest-filter=feature_tests/collections/22_dynamic_array_borrowed_index_string\n"
)
