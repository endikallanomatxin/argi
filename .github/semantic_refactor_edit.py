from pathlib import Path

# Measurement-only harness state: source changes are already committed.
Path(".git/semantic-refactor-message").write_text("No source edit\n")
