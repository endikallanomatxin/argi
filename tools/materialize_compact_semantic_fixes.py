from pathlib import Path

# Materialize the semantic fixes that have already been validated by the
# compact-semantic-graph CI probe. This script is intentionally one-shot: the
# workflow that runs it commits the resulting source changes and removes this
# file again.

p = Path("src/4_semantics/module/initializer_lowerer.zig")
s = p.read_text()
old_calls = "    try ctx.lowerDeferredStructDefinitions();\n    try ctx.lowerDeferredFunctionInterfaces();"
new_calls = "    try ctx.lowerDeferredStructDefinitions();\n    try ctx.lowerDeferredChoiceDefinitions();\n    try ctx.lowerDeferredFunctionInterfaces();"
marker = "    fn lowerDeferredFunctionInterfaces(self: *Context) !void {"
helper = '''    /// Finish non-generic choice declarations whose payload types could not
    /// be represented by the compatibility builder because they cross a
    /// module boundary. Canonical ModuleSema can retain those types as
    /// ExternalRef-backed slots, so the declared choice shape stays complete.
    fn lowerDeferredChoiceDefinitions(self: *Context) !void {
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.kind != .type or declaration.choice_variants != null) continue;
            self.selectFile(declaration.module_file_index);
            const type_declaration = self.tree.typeDeclaration(declaration.syntax_node) orelse continue;
            if (type_declaration.generic_params.len != 0 or type_declaration.generic_params_struct != null) continue;
            const literal = self.tree.choiceTypeLiteral(type_declaration.value) orelse continue;
            const start: u32 = @intCast(views.variantCount(self.graph));
            for (literal.variants, 0..) |variant_node, index| {
                const variant = self.tree.choiceTypeVariant(variant_node) orelse return error.InvalidChoiceVariant;
                const name_text = self.tree.tokenTextFromSource(self.source, variant.name_token);
                var option_decl: ?entities.ModuleDeclId = null;
                if (variant.module_qualifier == null) {
                    for (self.graph.declarationsNamed(name_text)) |candidate| {
                        if (self.graph.declarations.items[@intFromEnum(candidate)].kind != .choice_option) continue;
                        option_decl = candidate;
                        break;
                    }
                }
                _ = try self.writer.addVariant(.{
                    .name = try self.writer.addString(name_text),
                    .payload_type = if (variant.payload_type) |payload| try self.lowerType(payload) else null,
                    .option_decl = option_decl,
                    .source = self.sourceRef(variant_node),
                    .value = @intCast(index),
                });
            }
            self.graph.declarations.items[raw].choice_variants = .{ .start = start, .len = @intCast(literal.variants.len) };
        }
    }

'''
assert s.count(old_calls) == 1
assert s.count(marker) == 1
p.write_text(s.replace(old_calls, new_calls, 1).replace(marker, helper + marker, 1))

p = Path("src/4_semantics/global/core.zig")
s = p.read_text()
old = '''                const reference = module.semantic.external_refs.items[@intFromEnum(external)];
                if (reference.kind != .type) continue;
                // Generic external references need parameterized substitution and are
                // intentionally claimed by the generic resolver instead.
                if (reference.generic_arguments != null) continue;
                const target = self.resolveDeclaration(module_index, reference, &.{ .type, .abstract_type }) catch continue;'''
new = '''                const reference = module.semantic.external_refs.items[@intFromEnum(external)];
                if (reference.kind != .type) continue;
                if (reference.module_path == null and reference.generic_arguments == null) {
                    const name = module.text(reference.name);
                    var resolved_builtin: ?primitives.BuiltinType = null;
                    inline for (@typeInfo(primitives.BuiltinType).@"enum".fields) |field| {
                        if (std.mem.eql(u8, name, field.name)) { resolved_builtin = @enumFromInt(field.value); break; }
                    }
                    if (resolved_builtin) |builtin_type| {
                        self.graph.types.items[@intFromEnum(globalizer.globalType(o, local_id))] = .{ .builtin = builtin_type };
                        self.stats.external_types += 1;
                        continue;
                    }
                }
                // Generic external references need parameterized substitution and are
                // intentionally claimed by the generic resolver instead.
                if (reference.generic_arguments != null) continue;
                const target = self.resolveDeclaration(module_index, reference, &.{ .type, .abstract_type }) catch continue;'''
assert s.count(old) == 1
p.write_text(s.replace(old, new, 1))

p = Path("src/4_semantics/global/ownership.zig")
s = p.read_text()
old = '''        const nodes = self.graph.node_refs.items[original.nodes.start..][0..original.nodes.len];
        for (nodes) |node_id| {'''
new = '''        // Recursive finalization appends cleanup edges to graph.node_refs and
        // may reallocate it. Keep a stable copy of this block's original node IDs.
        const nodes = try self.allocator.dupe(global_sg.GlobalNodeId, self.graph.node_refs.items[original.nodes.start..][0..original.nodes.len]);
        defer self.allocator.free(nodes);
        for (nodes) |node_id| {'''
assert s.count(old) == 1
p.write_text(s.replace(old, new, 1))

p = Path("src/4_semantics/global/abstracts.zig")
s = p.read_text()
old = '''        const registry_start: u32 = @intCast(self.graph.virtual_registries.items.len);
        for (methods.items, 0..) |_, index| try self.graph.virtual_registries.append(self.allocator, .{
            .implementations = .{ .start = method_start + @as(u32, @intCast(index)), .len = 1 },
        });
        const virtual_ty = try self.generics.internType(.{ .virtual = abstract_ty });'''
new = '''        // Virtualize.safety_methods is a range into virtual_registry_refs, not
        // directly into virtual_registries. Keep the indirection explicit so
        // later registries can be non-contiguous without corrupting the range.
        const safety_start: u32 = @intCast(self.graph.virtual_registry_refs.items.len);
        for (methods.items, 0..) |_, index| {
            const registry: global_sg.GlobalVirtualRegistryId = @enumFromInt(@as(u32, @intCast(self.graph.virtual_registries.items.len)));
            try self.graph.virtual_registries.append(self.allocator, .{
                .implementations = .{ .start = method_start + @as(u32, @intCast(index)), .len = 1 },
            });
            try self.graph.virtual_registry_refs.append(self.allocator, registry);
        }
        const virtual_ty = try self.generics.internType(.{ .virtual = abstract_ty });'''
old_range = "            .safety_methods = .{ .start = registry_start, .len = @intCast(methods.items.len) },"
new_range = "            .safety_methods = .{ .start = safety_start, .len = @intCast(methods.items.len) },"
assert s.count(old) == 1
assert s.count(old_range) == 1
p.write_text(s.replace(old, new, 1).replace(old_range, new_range, 1))

p = Path("src/4_semantics/safety/checker.zig")
s = p.read_text()
old_join = '''    fn joinState(self: *SafetyChecker, out: *FunctionState, left: *const FunctionState, right: *const FunctionState) !void {
        _ = self;
        // Root liveness is conservative: if either path ended it, joined state
        // cannot claim definitely-alive.
        const count = @min(left.tracker.roots.items.len, right.tracker.roots.items.len);
        for (0..count) |index| {
            const a = left.tracker.roots.items[index].state;
            const b = right.tracker.roots.items[index].state;
            out.tracker.roots.items[index].state = if (a == b) a else .maybe_alive;
        }
        for (out.places.items) |*place| {
            const a = findPlaceConst(left, place.storage);
            const b = findPlaceConst(right, place.storage);
            if (a == null or b == null) {
                place.initializedness = .maybe_initialized;
                continue;
            }
            if (a.?.initializedness != b.?.initializedness) place.initializedness = .maybe_initialized;
        }
        out.reachable = left.reachable or right.reachable;
    }'''
new_join = '''    fn joinState(self: *SafetyChecker, out: *FunctionState, left: *const FunctionState, right: *const FunctionState) !void {
        if (!left.reachable) return self.copyState(out, right);
        if (!right.reachable) return self.copyState(out, left);

        // Branches clone the same root namespace but may materialize additional
        // roots independently. Rebuild the joined root table to the widest
        // namespace instead of assuming the destination already has that size.
        var roots = std.array_list.Managed(facts.ValidityRoot).init(self.allocator);
        defer roots.deinit();
        const count = @max(left.tracker.roots.items.len, right.tracker.roots.items.len);
        for (0..count) |index| {
            const id: facts.ValidityRootId = @enumFromInt(index);
            const left_state: @TypeOf(left.tracker.roots.items[0].state) = if (index < left.tracker.roots.items.len)
                left.tracker.roots.items[index].state
            else if (self.storageGenerationWasOnlyMaterializedIn(id, right, left))
                .alive
            else
                .dead;
            const right_state: @TypeOf(right.tracker.roots.items[0].state) = if (index < right.tracker.roots.items.len)
                right.tracker.roots.items[index].state
            else if (self.storageGenerationWasOnlyMaterializedIn(id, left, right))
                .alive
            else
                .dead;
            const left_owned = index < left.tracker.roots.items.len and left.tracker.roots.items[index].owned_resource;
            const right_owned = index < right.tracker.roots.items.len and right.tracker.roots.items[index].owned_resource;
            try roots.append(.{
                .id = id,
                .state = if (left_state == right_state) left_state else .maybe_alive,
                .owned_resource = left_owned or right_owned,
            });
        }
        out.tracker.roots.clearRetainingCapacity();
        try out.tracker.roots.appendSlice(roots.items);

        for (out.places.items) |*place| {
            const a = findPlaceConst(left, place.storage);
            const b = findPlaceConst(right, place.storage);
            if (a == null or b == null) {
                place.initializedness = .maybe_initialized;
                continue;
            }
            if (a.?.initializedness != b.?.initializedness) place.initializedness = .maybe_initialized;
        }
        out.reachable = true;
    }

    /// Storage generations are created lazily when a Place first needs one. If
    /// only one branch materialized that fact, the other branch still preserves
    /// the same live storage generation while the Place itself is initialized.
    fn storageGenerationWasOnlyMaterializedIn(
        self: *SafetyChecker,
        root: facts.ValidityRootId,
        materialized: *const FunctionState,
        other: *const FunctionState,
    ) bool {
        _ = self;
        var storage: ?facts.Place = null;
        for (materialized.storage_generations.items) |entry| if (entry.generation == root) {
            storage = entry.storage;
            break;
        };
        const target = storage orelse return false;
        for (other.storage_generations.items) |entry| if (entry.storage.eql(target)) return false;

        var projection_count = target.projections.len;
        while (true) {
            const prefix = facts.Place{ .root = target.root, .projections = target.projections[0..projection_count] };
            if (findPlaceConst(other, prefix)) |stored| return stored.initializedness == .initialized;
            if (projection_count == 0) return false;
            projection_count -= 1;
        }
    }'''
assert s.count(old_join) == 1
p.write_text(s.replace(old_join, new_join, 1))

clean_workflow = '''name: Compact semantic graph

on:
  push:
    branches:
      - compact-semantic-graph-chatgpt
  workflow_dispatch:

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-24.04
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Zig
        uses: mlugg/setup-zig@v2
        with:
          version: 0.16.0

      - name: Install LLVM 21
        run: |
          sudo apt-get update
          sudo apt-get install -y wget ca-certificates gnupg
          wget -q https://apt.llvm.org/llvm.sh
          chmod +x llvm.sh
          sudo ./llvm.sh 21
          sudo apt-get install -y llvm-21-dev clang-21

      - name: Build compiler
        run: zig build

      - name: Run internal tests
        timeout-minutes: 5
        run: zig build test-internal

      - name: Run program suite
        timeout-minutes: 15
        run: zig build test-programs
'''
Path(".github/workflows/compact-semantic-graph.yml").write_text(clean_workflow)
Path(__file__).unlink()
