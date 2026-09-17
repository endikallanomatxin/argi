from pathlib import Path

# Source edits from the previous parity fix have landed. Keep this harness free
# of stale source anchors and use it only to select the next focused probe.
Path(".git/semantic-refactor-test-command").write_text(
    "status=0\n"
    "zig build test-programs -Dtest-filter=feature_tests/collections/2 || status=1\n"
    "zig build test-programs -Dtest-filter=feature_tests/collections/3 || status=1\n"
    "exit $status\n"
)
