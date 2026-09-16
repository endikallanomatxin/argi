from pathlib import Path

checker = Path("src/4_semantics/safety/checker.zig")
text = checker.read_text()

# Stored choice values already carry a known discriminant. Payload safety may
# use either that concrete value fact or a control-flow refinement.
start = text.index("    fn evaluateChoicePayload(")
end = text.index("\n    fn ", start + 5)
segment = text[start:end]
old = "            if (!self.variantActive(state, storage, wanted)) {"
new = "            if (choice.known_choice_variant != wanted and !self.variantActive(state, storage, wanted)) {"
if segment.count(old) != 1:
    raise RuntimeError(f"choice payload refinement anchor changed: {segment.count(old)}")
segment = segment.replace(old, new, 1)
text = text[:start] + segment + text[end:]

# Opaque reads of pointer-free aggregates must discard lifetime/ownership facts,
# but the aggregate's semantic shape is still real information. Previously the
# scalar fast path erased fields, variants and known_choice_variant wholesale.
old = '''        const value_type = ty orelse return value;
        if (!self.typeContainsPointer(value_type)) return value.scalarOpaqueRead();
        // A projected pointer borrows its parent's generation. Conservative
'''
new = '''        const value_type = ty orelse return value;
        if (!self.typeContainsPointer(value_type)) return self.nonPointerOpaqueRead(value, value_type);
        // A projected pointer borrows its parent's generation. Conservative
'''
if text.count(old) != 1:
    raise RuntimeError(f"opaque read fast-path anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

anchor = '''        return result;
    }

    fn fieldTypeAt(
'''
helper = '''        return result;
    }

    /// Remove lifetime/ownership facts from a pointer-free opaque read while
    /// preserving structural value facts. Choice discriminants and aggregate
    /// projections describe the value itself, not the storage envelope that
    /// happened to contain it.
    fn nonPointerOpaqueRead(
        self: *SafetyChecker,
        value: facts.ValueFacts,
        ty: graph_mod.GlobalTypeId,
    ) !facts.ValueFacts {
        var result = value.scalarOpaqueRead();
        result.known_choice_variant = value.known_choice_variant;

        if (value.fields.len != 0) {
            const fields = try self.allocator.alloc(facts.FieldFacts, value.fields.len);
            for (value.fields, 0..) |field, index| {
                const stored = try self.allocator.create(facts.ValueFacts);
                stored.* = if (self.fieldTypeAt(ty, field.index)) |field_ty|
                    try self.nonPointerOpaqueRead(field.value.*, field_ty)
                else
                    field.value.scalarOpaqueRead();
                fields[index] = .{ .index = field.index, .value = stored };
            }
            result.fields = fields;
        }
        if (value.variants.len != 0) {
            const variants = try self.allocator.alloc(facts.VariantFacts, value.variants.len);
            for (value.variants, 0..) |variant, index| {
                const stored = try self.allocator.create(facts.ValueFacts);
                stored.* = if (self.variantPayloadTypeAt(ty, variant.index)) |payload_ty|
                    try self.nonPointerOpaqueRead(variant.value.*, payload_ty)
                else
                    variant.value.scalarOpaqueRead();
                variants[index] = .{ .index = variant.index, .value = stored };
            }
            result.variants = variants;
        }
        return result;
    }

    fn fieldTypeAt(
'''
if text.count(anchor) != 1:
    raise RuntimeError(f"opaque read helper anchor changed: {text.count(anchor)}")
text = text.replace(anchor, helper, 1)
checker.write_text(text)

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/types/03_choice_payloads "
    "-Dtest-filter=feature_tests/ownership/94_choice_if_narrowing "
    "-Dtest-filter=feature_tests/ownership/95X_choice_unproven_payload "
    "-Dtest-filter=feature_tests/ownership/96_choice_comparison_narrowing\n"
)
Path(".git/semantic-refactor-message").write_text("Preserve structural facts across opaque reads\n")
