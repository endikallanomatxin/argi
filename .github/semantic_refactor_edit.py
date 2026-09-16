from pathlib import Path

# Make the new terminal state part of the documented resolver contract.
resolution = Path("src/4_semantics/global/resolution.zig")
text = resolution.read_text()
old = '''    /// At the GlobalSema boundary every PendingOperation has one stable owner;
    /// `deferred` means that owner is waiting for semantic dependencies and
    /// `resolved` means it has completed the operation.
'''
new = '''    /// At the GlobalSema boundary every PendingOperation has one stable owner;
    /// `deferred` means that owner is waiting for semantic dependencies,
    /// `invalid` means all required information is present but the operation is
    /// semantically impossible and awaits a source diagnostic, and `resolved`
    /// means it has completed the operation.
'''
if text.count(old) != 1:
    raise RuntimeError(f"resolution contract anchor changed: {text.count(old)}")
resolution.write_text(text.replace(old, new, 1))

# Terminal-invalid work remains available to the final diagnostic pass, but it
# must not count as another semantic attempt on subsequent fixed-point rounds.
semantizer = Path("src/4_semantics/global/semantizer.zig")
text = semantizer.read_text()
old = '''        pending_attempts.* += 1;
        const module_index: usize = @intCast(item.module_index);
        const operation_index: usize = @intCast(item.operation_index);
        const flat_index: usize = @intCast(item.flat_index);
        if (invalid[flat_index]) {
            work.items[write] = item;
            write += 1;
            continue;
        }
        const module = &modules[module_index];
'''
new = '''        const module_index: usize = @intCast(item.module_index);
        const operation_index: usize = @intCast(item.operation_index);
        const flat_index: usize = @intCast(item.flat_index);
        if (invalid[flat_index]) {
            work.items[write] = item;
            write += 1;
            continue;
        }
        pending_attempts.* += 1;
        const module = &modules[module_index];
'''
if text.count(old) != 1:
    raise RuntimeError(f"pending-attempt anchor changed: {text.count(old)}")
semantizer.write_text(text.replace(old, new, 1))

control = Path("src/4_semantics/global/control.zig")
text = control.read_text()
old = '''            .resolve_choice_literal => |value| resolution.Result.fromBool(try self.resolveChoiceLiteral(module, o, value)),
            .resolve_choice_payload => |value| resolution.Result.fromBool(try self.resolveChoicePayload(module, o, value)),
'''
new = '''            .resolve_choice_literal => |value| try self.resolveChoiceLiteral(module, o, value),
            .resolve_choice_payload => |value| try self.resolveChoicePayload(module, o, value),
'''
if text.count(old) != 1:
    raise RuntimeError(f"choice dispatch anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

start = text.index("    fn resolveChoiceLiteral(")
end = text.index("\n    fn ensureInferredReasonVariant", start)
new_function = '''    fn resolveChoiceLiteral(self: *Resolver, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.option)];
        const name = module.text(reference.name);
        const payload = if (value.payload) |id| globalizer.globalNode(o, id) else null;
        var payload_ty = if (payload) |id| self.graph.nodes.items[@intFromEnum(id)].ty else null;
        const target = globalizer.globalNode(o, value.node);
        if (self.graph.nodes.items[@intFromEnum(target)].content == .int_literal) return .resolved;
        const expected = if (value.expected_type) |id| globalizer.globalType(o, id) else self.graph.nodes.items[@intFromEnum(target)].ty;

        // An explicit contextual type is authoritative. Shape errors that can
        // no longer change (unknown variant, or a required payload being
        // absent) are terminal-invalid; unresolved payload typing remains
        // deferred so coercion/generic resolution can still make progress.
        const choice_ty = blk: {
            if (expected) |expected_ty| {
                if (!self.graph.isTypeUnresolved(expected_ty) and !types.isBuiltin(self.graph, expected_ty, .Any)) {
                    try self.ensureInferredReasonVariant(expected_ty, name, self.sourceFor(reference.source, o));
                    if (types.findVariant(self.graph, expected_ty, name)) |hit| {
                        if (hit.variant.payload_type != null and payload == null) return .invalid;
                        if (payload) |payload_node| if (hit.variant.payload_type) |expected_payload| {
                            if (self.core) |core| _ = core.coerceContextualValue(payload_node, expected_payload);
                            payload_ty = self.graph.nodes.items[@intFromEnum(payload_node)].ty;
                        };
                        if (!self.payloadCompatible(hit.variant.payload_type, payload_ty)) return .deferred;
                        break :blk expected_ty;
                    }
                    if (value.expected_type != null and types.variants(self.graph, expected_ty) != null) return .invalid;
                }
            }
            break :blk self.findChoiceType(expected, name, payload_ty) orelse return .deferred;
        };

        const variant = types.findVariant(self.graph, choice_ty, name) orelse return .deferred;
        if (payload) |payload_node| if (variant.variant.payload_type) |expected_payload| {
            if (self.core) |core| _ = core.coerceContextualValue(payload_node, expected_payload);
            payload_ty = self.graph.nodes.items[@intFromEnum(payload_node)].ty;
        };
        if (!self.payloadCompatible(variant.variant.payload_type, payload_ty)) return .deferred;
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.sourceFor(reference.source, o),
            .ty = choice_ty,
            .content = .{ .choice_literal = .{
                .choice_type = choice_ty,
                .variant = variant.id,
                .payload = payload,
            } },
        };
        self.stats.choices += 1;
        return .resolved;
    }
'''
text = text[:start] + new_function + text[end:]

start = text.index("    fn resolveChoicePayload(")
end = text.index("\n    fn resolveNullableUnwrap", start)
new_function = '''    fn resolveChoicePayload(self: *Resolver, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const source = globalizer.globalNode(o, value.value);
        const choice_ty = self.graph.nodes.items[@intFromEnum(source)].ty orelse return .deferred;
        if (self.graph.isTypeUnresolved(choice_ty)) return .deferred;
        const name = module.text(value.option_name);
        const hit = types.findVariant(self.graph, choice_ty, name) orelse return .deferred;
        const payload_ty = hit.variant.payload_type orelse return .invalid;
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.sourceFor(value.source, o),
            .ty = payload_ty,
            .content = .{ .choice_payload_access = .{
                .value = source,
                .variant = hit.id,
                .payload_type = payload_ty,
            } },
        };
        self.stats.choices += 1;
        return .resolved;
    }
'''
text = text[:start] + new_function + text[end:]
control.write_text(text)

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/types/01_choice "
    "-Dtest-filter=feature_tests/types/03_choice_payloads "
    "-Dtest-filter=feature_tests/types/04X_choice_missing_payload "
    "-Dtest-filter=feature_tests/types/10X_choice_unknown_variant "
    "-Dtest-filter=feature_tests/types/11X_choice_payload_access_without_payload "
    "-Dtest-filter=feature_tests/functions/18_choice_variant_equality\n"
)
Path(".git/semantic-refactor-message").write_text("Classify terminal choice resolution failures\n")
