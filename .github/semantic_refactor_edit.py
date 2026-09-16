from pathlib import Path

ownership = Path("src/4_semantics/global/ownership.zig")
text = ownership.read_text()
old = '''            .structural, .declared => blk: {
                const fields = global_types.fields(self.graph, ty) orelse break :blk false;
                for (self.graph.fields.items[fields.start..][0..fields.len]) |field|
                    if (!self.triviallyCopyable(field.ty)) break :blk false;
                break :blk true;
            },
'''
new = '''            .structural => blk: {
                const fields = global_types.fields(self.graph, ty) orelse break :blk false;
                break :blk self.fieldsTriviallyCopyable(fields);
            },
            .declared => blk: {
                if (global_types.fields(self.graph, ty)) |fields|
                    break :blk self.fieldsTriviallyCopyable(fields);
                if (global_types.variants(self.graph, ty)) |variants|
                    break :blk self.variantsTriviallyCopyable(variants);
                break :blk false;
            },
'''
if text.count(old) != 1:
    raise RuntimeError(f"declared copyability anchor changed: {text.count(old)}")
ownership.write_text(text.replace(old, new, 1))

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/ownership/97_choice_nested_narrowing "
    "-Dtest-filter=feature_tests/ownership/98X_choice_nested_unproven_payload "
    "-Dtest-filter=feature_tests/types/32X_match_value_noncopyable_payload "
    "-Dtest-filter=feature_tests/types/03_choice_payloads\n"
)
Path(".git/semantic-refactor-message").write_text("Recognize declared choice copyability\n")
