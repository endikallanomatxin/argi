from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected pattern not found in {path}: {old!r}")
    file.write_text(text.replace(old, new))


# Safety no longer needs the enclosing function identity for auto-deinit.
replace(
    "src/4_semantics/global_safety_checker.zig",
    "    fn applyAutoDeinit(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, id: graph_mod.GlobalAutoDeinitId, state: *FunctionState) !void {\n        const cleanup",
    "    fn applyAutoDeinit(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, id: graph_mod.GlobalAutoDeinitId, state: *FunctionState) !void {\n        _ = function;\n        const cleanup",
)

# Zig 0.16 does not implicitly lift !bool into !?bool. Normalize every
# GlobalSema fixpoint resolver so they all implement the same protocol.
replace(
    "src/4_semantics/global_semantic_core.zig",
    "            .resolve_type => |value| self.resolveTypeHole(module_index, module, o, value),",
    "            .resolve_type => |value| @as(?bool, try self.resolveTypeHole(module_index, module, o, value)),",
)
for old, new in [
    ("            .resolve_call => |value| self.resolveCall(module_index, module, o, value),", "            .resolve_call => |value| @as(?bool, try self.resolveCall(module_index, module, o, value)),"),
    ("            .resolve_field => |value| self.resolveField(module, o, value),", "            .resolve_field => |value| @as(?bool, try self.resolveField(module, o, value)),"),
    ("            .resolve_binary => |value| self.resolveBinary(module_index, o, value),", "            .resolve_binary => |value| @as(?bool, try self.resolveBinary(module_index, o, value)),"),
    ("            .resolve_comparison => |value| self.resolveComparison(module_index, o, value),", "            .resolve_comparison => |value| @as(?bool, try self.resolveComparison(module_index, o, value)),"),
    ("            .resolve_index => |value| self.resolveIndex(module_index, o, value),", "            .resolve_index => |value| @as(?bool, try self.resolveIndex(module_index, o, value)),"),
]:
    replace("src/4_semantics/global_semantic_core.zig", old, new)

replace(
    "src/4_semantics/global_semantic_generics.zig",
    "            .resolve_type => |value| self.resolveGenericTypeHole(module_index, module, o, value),",
    "            .resolve_type => |value| @as(?bool, try self.resolveGenericTypeHole(module_index, module, o, value)),",
)
replace(
    "src/4_semantics/global_semantic_generic_functions.zig",
    "            .resolve_call => |value| self.resolveModuleGenericCall(module_index, module, o, value),",
    "            .resolve_call => |value| @as(?bool, try self.resolveModuleGenericCall(module_index, module, o, value)),",
)

for old, new in [
    ("            .resolve_choice_literal => |value| try self.resolveChoiceLiteral(module, o, value),", "            .resolve_choice_literal => |value| @as(?bool, try self.resolveChoiceLiteral(module, o, value)),"),
    ("            .resolve_choice_payload => |value| try self.resolveChoicePayload(module, o, value),", "            .resolve_choice_payload => |value| @as(?bool, try self.resolveChoicePayload(module, o, value)),"),
    ("            .resolve_nullable_unwrap => |value| try self.resolveNullableUnwrap(o, value),", "            .resolve_nullable_unwrap => |value| @as(?bool, try self.resolveNullableUnwrap(o, value)),"),
    ("            .resolve_nullable_test => |value| try self.resolveNullableTest(o, value),", "            .resolve_nullable_test => |value| @as(?bool, try self.resolveNullableTest(o, value)),"),
    ("            .resolve_match => |value| try self.resolveMatch(module, o, value),", "            .resolve_match => |value| @as(?bool, try self.resolveMatch(module, o, value)),"),
    ("            .resolve_match_case => |value| self.matchCaseAlreadyResolved(o, value),", "            .resolve_match_case => |value| @as(?bool, self.matchCaseAlreadyResolved(o, value)),"),
    ("            .resolve_for_each => |value| try self.resolveForEach(module_index, o, value),", "            .resolve_for_each => |value| @as(?bool, try self.resolveForEach(module_index, o, value)),"),
]:
    replace("src/4_semantics/global_semantic_control.zig", old, new)

replace(
    "src/4_semantics/global_semantic_errors.zig",
    "            .resolve_error_propagation => |value| try self.resolve(o, value),",
    "            .resolve_error_propagation => |value| @as(?bool, try self.resolve(o, value)),",
)
for old, new in [
    ("            .resolve_defer => |value| try self.resolveDefer(o, value),", "            .resolve_defer => |value| @as(?bool, try self.resolveDefer(o, value)),"),
    ("            .resolve_keep => |value| try self.resolveKeep(o, value),", "            .resolve_keep => |value| @as(?bool, try self.resolveKeep(o, value)),"),
    ("            .resolve_copy => |value| try self.resolveCopy(o, value),", "            .resolve_copy => |value| @as(?bool, try self.resolveCopy(o, value)),"),
    ("            .resolve_deinit => |value| try self.resolveExplicitDeinit(o, value),", "            .resolve_deinit => |value| @as(?bool, try self.resolveExplicitDeinit(o, value)),"),
]:
    replace("src/4_semantics/global_semantic_ownership.zig", old, new)

replace(
    "src/4_semantics/global_semantic_abstracts.zig",
    "                const ty = self.graph.declarations.items[@intFromEnum(declaration)].type_id orelse break :blk false;",
    "                const ty = self.graph.declarations.items[@intFromEnum(declaration)].type_id orelse break :blk @as(?bool, false);",
)
replace(
    "src/4_semantics/global_semantic_abstracts.zig",
    "                break :blk try self.implements(ty, abstract_decl);",
    "                break :blk @as(?bool, try self.implements(ty, abstract_decl));",
)

# For-each and match use distinct nominal mode enums. Keep their lowering
# separate instead of coercing unrelated enums just because their cases overlap.
replace(
    "src/4_semantics/global_semantic_control.zig",
    "        const assigned_ty = try self.matchBindingType(element_ty, value.mode);",
    "        const assigned_ty = try self.forBindingType(element_ty, value.mode);",
)
replace(
    "src/4_semantics/global_semantic_control.zig",
    "    fn matchBindingType(self: *Resolver, payload: global_sg.GlobalTypeId, mode: syn.MatchCaseMode) !global_sg.GlobalTypeId {\n        return switch (mode) {\n            .value, .move => payload,\n            .borrow => self.pointer(payload, .read_only),\n            .mut_borrow => self.pointer(payload, .read_write),\n        };\n    }",
    "    fn matchBindingType(self: *Resolver, payload: global_sg.GlobalTypeId, mode: syn.MatchCaseMode) !global_sg.GlobalTypeId {\n        return switch (mode) {\n            .value, .move => payload,\n            .borrow => self.pointer(payload, .read_only),\n            .mut_borrow => self.pointer(payload, .read_write),\n        };\n    }\n\n    fn forBindingType(self: *Resolver, payload: global_sg.GlobalTypeId, mode: syn.ForMode) !global_sg.GlobalTypeId {\n        return switch (mode) {\n            .value => payload,\n            .borrow => self.pointer(payload, .read_only),\n            .mut_borrow => self.pointer(payload, .read_write),\n        };\n    }",
)

# Keep generic-function comparison lowering aligned with the canonical token
# operator enum names used everywhere else in the indexed graph.
for old, new in [
    ("                .compare_less => .less,", "                .compare_less => .less_than,"),
    ("                .compare_greater => .greater,", "                .compare_greater => .greater_than,"),
    ("                .compare_less_equal => .less_equal,", "                .compare_less_equal => .less_than_or_equal,"),
    ("                .compare_greater_equal => .greater_equal,", "                .compare_greater_equal => .greater_than_or_equal,"),
]:
    replace("src/4_semantics/global_semantic_generic_functions.zig", old, new)

# SourceDb cleanup is mutating, so the cloned database must remain mutable until
# ownership is transferred into the returned Analysis.
replace(
    "src/0_commands/indexed_lsp_service.zig",
    "        const db = try diagnostics.source_db.clone(allocator.*);\n        errdefer db.deinit(allocator.*);",
    "        var db = try diagnostics.source_db.clone(allocator.*);\n        errdefer db.deinit(allocator.*);",
)

# Zig 0.16's managed ArrayList no longer exposes the old writer().print API.
# Centralize formatted appends so mangling keeps using the managed buffer.
replace(
    "src/5_codegen/global_codegen_types.zig",
    "    pub fn encodeType(self: *Lowerer, buffer: *std.array_list.Managed(u8), ty: graph_mod.GlobalTypeId) !void {",
    "    fn appendPrint(self: *Lowerer, buffer: *std.array_list.Managed(u8), comptime format: []const u8, args: anytype) !void {\n        const text = try std.fmt.allocPrint(self.allocator, format, args);\n        defer self.allocator.free(text);\n        try buffer.appendSlice(text);\n    }\n\n    pub fn encodeType(self: *Lowerer, buffer: *std.array_list.Managed(u8), ty: graph_mod.GlobalTypeId) !void {",
)
for old, new in [
    ("                try buffer.writer().print(\"arr{d}_\", .{array.length});", "                try self.appendPrint(buffer, \"arr{d}_\", .{array.length});"),
    ("                try buffer.writer().print(\"{d}_\", .{@intFromEnum(decl)});", "                try self.appendPrint(buffer, \"{d}_\", .{@intFromEnum(decl)});"),
    ("            .inferred_choice => |shape| try buffer.writer().print(\"choice_i{d}\", .{shape.identity}),", "            .inferred_choice => |shape| try self.appendPrint(buffer, \"choice_i{d}\", .{shape.identity}),"),
    ("                try buffer.writer().print(\"g{d}\", .{@intFromEnum(identity.base)});", "                try self.appendPrint(buffer, \"g{d}\", .{@intFromEnum(identity.base)});"),
    ("                    .comptime_int => |value| try buffer.writer().print(\"_n{d}\", .{value}),", "                    .comptime_int => |value| try self.appendPrint(buffer, \"_n{d}\", .{value}),"),
    ("        try buffer.writer().print(\"__f{d}__in_\", .{@intFromEnum(function_id)});", "        try self.appendPrint(&buffer, \"__f{d}__in_\", .{@intFromEnum(function_id)});"),
]:
    replace("src/5_codegen/global_codegen_types.zig", old, new)

# TemplateIR resolved shapes are the shared semantic type instantiated with Template IDs.
replace(
    "src/4_semantics/module_semantic_template_ir.zig",
    "pub const Field = primitives.Field(Ids);",
    "pub const ResolvedType = primitives.SemanticType(Ids);\npub const Field = primitives.Field(Ids);",
)

# LSP facade returns an optional owned slice; unwrap allocation failure first.
replace(
    "src/0_commands/lsp_service.zig",
    "    return output.toOwnedSlice();",
    "    return try output.toOwnedSlice();",
)
