from pathlib import Path

# Measurement-only run. The semantic source is already at the lexical-import
# commit; this harness invocation only exercises the next diagnostic cluster.
Path(".git/semantic-refactor-message").write_text("Measure local import diagnostics\n")
