from pathlib import Path

checker = Path("src/4_semantics/safety/checker.zig")
text = checker.read_text()

start = text.index("    fn evaluateChoicePayload(")
end = text.index("\n    fn ", start + 5)
segment = text[start:end]
old = "            if (!self.variantActive(state, storage, wanted)) {"
new = "            if (choice.known_choice_variant != wanted and !self.variantActive(state, storage, wanted)) {"
if segment.count(old) != 1:
    raise RuntimeError(f"choice payload refinement anchor changed: {segment.count(old)}")
segment = segment.replace(old, new, 1)
text = text[:start] + segment + text[end:]
checker.write_text(text)

# Keep the validation gate colocated with the edit so a single harness commit
# always runs the intended adversarial set.
Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/types/03_choice_payloads "
    "-Dtest-filter=feature_tests/ownership/94_choice_if_narrowing "
    "-Dtest-filter=feature_tests/ownership/95X_choice_unproven_payload "
    "-Dtest-filter=feature_tests/ownership/96_choice_comparison_narrowing "
    "-Dtest-filter=feature_tests/ownership/97_choice_nested_narrowing "
    "-Dtest-filter=feature_tests/ownership/98X_choice_nested_unproven_payload\n"
)
Path(".git/semantic-refactor-message").write_text("Use known choice variants for payload safety\n")
