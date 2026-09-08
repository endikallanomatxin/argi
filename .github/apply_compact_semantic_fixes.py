from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected pattern not found in {path}: {old!r}")
    file.write_text(text.replace(old, new))


# Zig 0.16 mechanical diagnostics in indexed Safety.
path = "src/4_semantics/global_safety_checker.zig"
replace(path,
    "const value = if (record.initialization) |init| try self.evaluate(function, init, state) else facts.ValueFacts{};",
    "const value = if (record.initialization) |initialization| try self.evaluate(function, initialization, state) else facts.ValueFacts{};")
replace(path,
    "if (statement.init) |init| _ = try self.evaluate(function, init, state);",
    "if (statement.init) |initialization| _ = try self.evaluate(function, initialization, state);")
replace(path,
    "        _ = function;\n        return switch (primitive) {",
    "        _ = function;\n        _ = argument_ids;\n        return switch (primitive) {")
replace(path,
    "if (cleanup.deinit_fn) |deinit| {",
    "if (cleanup.deinit_fn) |deinit_fn| {")
replace(path,
    "const fn_record = self.graph.functions.items[@intFromEnum(deinit)];",
    "const fn_record = self.graph.functions.items[@intFromEnum(deinit_fn)];")
replace(path,
    "if (fn_record.body) |body| try self.validateBlock(deinit, body, &candidate);",
    "if (fn_record.body) |body| try self.validateBlock(deinit_fn, body, &candidate);")
replace(path,
    "    fn storageGeneration(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) !facts.ValidityRootId {\n        for",
    "    fn storageGeneration(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) !facts.ValidityRootId {\n        _ = self;\n        for")
replace(path,
    "    fn setPlace(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, initializedness: value_state.Initializedness, value: facts.ValueFacts) !void {\n        for",
    "    fn setPlace(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, initializedness: value_state.Initializedness, value: facts.ValueFacts) !void {\n        _ = self;\n        for")
replace(path,
    "    fn getPlace(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) ?*facts.PlaceFacts {\n        for",
    "    fn getPlace(self: *SafetyChecker, state: *FunctionState, storage: facts.Place) ?*facts.PlaceFacts {\n        _ = self;\n        for")
replace(path,
    "var clone = try source.clone(self.allocator, if (self.collect_stats) &self.stats else null);",
    "const clone = try source.clone(self.allocator, if (self.collect_stats) &self.stats else null);")
replace(path,
    "    fn setActiveVariant(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, index: u32) void {\n        for",
    "    fn setActiveVariant(self: *SafetyChecker, state: *FunctionState, storage: facts.Place, index: u32) void {\n        _ = self;\n        for")
replace(path,
    "    fn globalValueFieldIds(self: *SafetyChecker, range: primitives.Range(graph_mod.GlobalValueFieldId)) []const graph_mod.GlobalValueFieldId {\n        _ = self;\n        // ValueFieldId",
    "    fn globalValueFieldIds(self: *SafetyChecker, range: primitives.Range(graph_mod.GlobalValueFieldId)) []const graph_mod.GlobalValueFieldId {\n        // ValueFieldId")

# Use the canonical typed type-reference range instead of an anonymous struct.
path = "src/4_semantics/module_semantic_entities.zig"
replace(path,
    "pub const BindingRange = primitives.Range(ModuleBindingId);\npub const NodeRange = primitives.Range(ModuleNodeId);",
    "pub const BindingRange = primitives.Range(ModuleBindingId);\npub const TypeRange = primitives.Range(ModuleTypeId);\npub const NodeRange = primitives.Range(ModuleNodeId);")
path = "src/4_semantics/module_semantic_writer.zig"
replace(path,
    "pub fn appendTypeRefs(self: *Writer, values: []const entities.ModuleTypeId) !struct { start: u32, len: u32 } {",
    "pub fn appendTypeRefs(self: *Writer, values: []const entities.ModuleTypeId) !entities.TypeRange {")

# Verify every pending semantic state ModuleSema is allowed to emit.
path = "src/4_semantics/module_semantic_verify.zig"
replace(path,
    "        .resolve_abstract => |value| {",
    """        .resolve_nullable_test => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
        },
        .resolve_for_each => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.binding, semantic.bindings.items.len));
            try require(verify.idFits(value.iterable, semantic.nodes.items.len));
            try require(verify.idFits(value.body, semantic.blocks.items.len));
        },
        .resolve_match => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
            try require(verify.rangeFits(value.cases, semantic.node_refs.items.len));
        },
        .resolve_match_case => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.option, semantic.external_refs.items.len));
            try require(semantic.external_refs.items[@intFromEnum(value.option)].kind == .choice_option);
            try require(verify.optionalIdFits(value.payload_binding, semantic.bindings.items.len));
            try require(verify.idFits(value.body, semantic.blocks.items.len));
        },
        .resolve_defer => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
        },
        .resolve_keep => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.binding, semantic.bindings.items.len));
        },
        .resolve_expression => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.rangeFits(value.operands, semantic.node_refs.items.len));
            if (value.name) |name| try require(verify.stringFits(name, graph.strings.items));
            try require(verify.optionalIdFits(value.expected_type, views.typeCount(graph)));
        },
        .resolve_abstract => |value| {""")

# Runtime variables need an explicit integer type in Zig 0.16.
for path in [
    "src/4_semantics/module_template_block_normalizer.zig",
    "src/4_semantics/module_template_call_metadata.zig",
]:
    replace(path, "var end = std.math.maxInt(u32);", "var end: u32 = std.math.maxInt(u32);")

# Break recursive layout error-set inference explicitly.
path = "src/4_semantics/global_semantic_types.zig"
replace(path,
    "pub const Layout = struct {\n    size: u64,\n    alignment: u64,\n};",
    """pub const Layout = struct {
    size: u64,
    alignment: u64,
};

pub const LayoutError = error{
    UnmaterializedGlobalType,
    UnmaterializedGenericType,
    TypeHasNoRuntimeLayout,
};""")
replace(path,
    "pub fn layoutOf(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) !Layout {",
    "pub fn layoutOf(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) LayoutError!Layout {")
replace(path,
    "fn declaredLayout(graph: *const graph_mod.GlobalSemanticGraph, decl_id: graph_mod.GlobalDeclId) !Layout {",
    "fn declaredLayout(graph: *const graph_mod.GlobalSemanticGraph, decl_id: graph_mod.GlobalDeclId) LayoutError!Layout {")
replace(path,
    "fn genericLayout(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) !Layout {",
    "fn genericLayout(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) LayoutError!Layout {")
replace(path,
    "fn structLayout(graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.FieldRange, kind: primitives.StructLayout) !Layout {",
    "fn structLayout(graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.FieldRange, kind: primitives.StructLayout) LayoutError!Layout {")
replace(path,
    "fn choiceLayout(graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.VariantRange, kind: primitives.ChoiceLayout) !Layout {",
    "fn choiceLayout(graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.VariantRange, kind: primitives.ChoiceLayout) LayoutError!Layout {")

# Coerce the owned path slice after unwrapping its allocation error.
path = "src/0_commands/indexed_lsp_service.zig"
replace(path, "return output.toOwnedSlice();", "return try output.toOwnedSlice();")
