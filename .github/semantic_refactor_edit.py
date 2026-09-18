from pathlib import Path

# Probe the post-refactor DynamicArray neighborhood without modifying source.
Path(".git/semantic-refactor-test-command").write_text(
    "status=0; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/2 || status=1; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/3 || status=1; "
    "exit $status\n"
)
