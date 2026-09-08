const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const module_views = @import("module_semantic_views.zig");
const global_sg = @import("global_semantic_graph.zig");
const globalizer = @import("semantic_globalizer.zig");
const types = @import("global_semantic_types.zig");
const callable = @import("semantic_callable.zig");
const primitives = @import("semantic_primitives.zig");

pub const Stats = struct {
    external_types: u32 = 0,
    calls: u32 = 0,
    fields: u32 = 0,
    operators: u32 = 0,
    indexes: u32 = 0,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    stats: Stats = .{},

    pub fn resolveExternalTypes(self: *Resolver) !void {
        for (self.modules, 0..) |*module, module_index| {
            const o = self.offsets[module_index];
            for (0..module_views.typeCount(module)) |raw_type| {
                const local_id: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw_type)));
                const value = try module_views.typeView(module, local_id);
                const external = switch (value) {
                    .external => |id| id,
                    .resolved => continue,
                };
                const reference = module.semantic.external_refs.items[@intFromEnum(external)];
                if (reference.kind != .type) continue;
                // Generic external references need template substitution and are
                // intentionally claimed by the generic resolver instead.
                if (reference.generic_arguments != null) continue;
                const target = self.resolveDeclaration(module_index, reference, &.{ .type, .abstract_type }) catch continue;
                const target_type = self.graph.declarations.items[@intFromEnum(target)].type_id orelse continue;
                self.graph.types.items[@intFromEnum(globalizer.globalType(o, local_id))] = .{ .declared = target };
                _ = target_type;
                self.stats.external_types += 1;
            }
        }
    }

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !?bool {
        return switch (operation) {
            .resolve_type => |value| @as(?bool, try self.resolveTypeHole(module_index, module, o, value)),
            .resolve_call => |value| self.resolveCall(module_index, module, o, value),
            .resolve_field => |value| self.resolveField(module, o, value),
            .resolve_binary => |value| self.resolveBinary(module_index, o, value),
            .resolve_comparison => |value| self.resolveComparison(module_index, o, value),
            .resolve_index => |value| self.resolveIndex(module_index, o, value),
            else => null,
        };
    }

    pub fn resolveDeclaration(
        self: *Resolver,
        current_module: usize,
        reference: module_entities.ExternalRef,
        kinds: []const primitives.DeclarationKind,
    ) !global_sg.GlobalDeclId {
        const module_filter = if (reference.module_path) |path|
            try self.findModuleBySpelling(self.modules[current_module].text(path))
        else
            null;
        const name = self.modules[current_module].text(reference.name);
        var found: ?global_sg.GlobalDeclId = null;
        for (self.graph.declarations.items, 0..) |decl, raw| {
            const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
            if (module_filter) |wanted| if (self.graph.moduleForDeclaration(id).? != wanted) continue;
            var allowed = false;
            for (kinds) |kind| if (decl.kind == kind) { allowed = true; break; };
            if (!allowed or !std.mem.eql(u8, self.graph.text(decl.name), name)) continue;
            if (found) |previous| {
                if (reference.module_path == null) {
                    const current: global_sg.GlobalModuleId = @enumFromInt(@as(u32, @intCast(current_module)));
                    const owner = self.graph.moduleForDeclaration(id).?;
                    const previous_owner = self.graph.moduleForDeclaration(previous).?;
                    if (owner == current and previous_owner != current) { found = id; continue; }
                    if (previous_owner == current and owner != current) continue;
                }
                return error.AmbiguousGlobalDeclaration;
            }
            found = id;
        }
        return found orelse error.UnknownGlobalDeclaration;
    }

    pub fn resolveFunctionByName(
        self: *Resolver,
        current_module: usize,
        reference: module_entities.ExternalRef,
        input_node: global_sg.GlobalNodeId,
    ) !global_sg.GlobalFunctionId {
        const module_filter = if (reference.module_path) |path|
            try self.findModuleBySpelling(self.modules[current_module].text(path))
        else
            null;
        const name = self.modules[current_module].text(reference.name);
        const input_ty = self.graph.nodes.items[@intFromEnum(input_node)].ty;
        var best: ?global_sg.GlobalFunctionId = null;
        var best_score: u32 = 0;
        var tied = false;
        for (self.graph.functions.items, 0..) |function, raw| {
            const decl = self.graph.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, self.graph.text(decl.name), name)) continue;
            if (module_filter) |wanted| if (self.graph.moduleForDeclaration(function.declaration).? != wanted) continue;
            const score = self.callScore(function, input_ty) orelse continue;
            if (best == null or score > best_score) {
                best = @enumFromInt(@as(u32, @intCast(raw)));
                best_score = score;
                tied = false;
            } else if (score == best_score) tied = true;
        }
        if (best == null) return error.NoMatchingGlobalFunction;
        if (tied) return error.AmbiguousGlobalFunction;
        return best.?;
    }

    pub fn resolveOperator(
        self: *Resolver,
        current_module: usize,
        operator: callable.OperatorKind,
        operand_types: []const global_sg.GlobalTypeId,
    ) !global_sg.GlobalFunctionId {
        var best: ?global_sg.GlobalFunctionId = null;
        var best_score: u32 = 0;
        var tied = false;
        for (self.graph.functions.items, 0..) |function, raw| {
            if (raw >= self.graph.function_operators.items.len or self.graph.function_operators.items[raw] != operator) continue;
            if (function.input.len != operand_types.len) continue;
            var score: u32 = 0;
            var compatible = true;
            for (operand_types, 0..) |actual, index| {
                const expected = self.graph.fields.items[function.input.start + @as(u32, @intCast(index))].ty;
                if (types.equal(self.graph, expected, actual)) score += 4
                else if (types.isBuiltin(self.graph, expected, .Any)) score += 1
                else { compatible = false; break; }
            }
            if (!compatible) continue;
            if (@intFromEnum(self.graph.moduleForDeclaration(function.declaration).?) == current_module) score += 1;
            if (best == null or score > best_score) {
                best = @enumFromInt(@as(u32, @intCast(raw)));
                best_score = score;
                tied = false;
            } else if (score == best_score) tied = true;
        }
        if (best == null) return error.NoMatchingGlobalFunction;
        if (tied) return error.AmbiguousGlobalFunction;
        return best.?;
    }

    pub fn functionOutputType(self: *Resolver, id: global_sg.GlobalFunctionId) !global_sg.GlobalTypeId {
        const function = self.graph.functions.items[@intFromEnum(id)];
        if (function.output.len == 0) return self.builtin(.Void);
        if (function.output.len == 1) return self.graph.fields.items[function.output.start].ty;
        return self.structType(function.output);
    }

    pub fn makeCallInput(self: *Resolver, function_id: global_sg.GlobalFunctionId, nodes: []const global_sg.GlobalNodeId) !global_sg.GlobalNodeId {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        if (nodes.len != function.input.len) return error.InvalidCallInputArity;
        const start: u32 = @intCast(self.graph.value_fields.items.len);
        for (nodes, 0..) |node, index| {
            const field = self.graph.fields.items[function.input.start + @as(u32, @intCast(index))];
            try self.graph.value_fields.append(self.allocator, .{ .name = field.name, .value = node });
        }
        const ty = try self.structType(function.input);
        const source = if (nodes.len != 0) self.graph.nodes.items[@intFromEnum(nodes[0])].source else self.syntheticSource();
        return self.appendNode(source, ty, .{ .struct_value_literal = .{
            .fields = .{ .start = start, .len = @intCast(nodes.len) },
            .ty = ty,
        } });
    }

    fn resolveTypeHole(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.external)];
        if (reference.generic_arguments != null) return false;
        const target = self.resolveDeclaration(module_index, reference, &.{ .type, .abstract_type }) catch return false;
        self.graph.types.items[@intFromEnum(globalizer.globalType(o, value.destination))] = .{ .declared = target };
        self.stats.external_types += 1;
        return true;
    }

    fn resolveCall(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        if (reference.generic_arguments != null) return false;
        const input = globalizer.globalNode(o, value.input);
        const function = self.resolveFunctionByName(module_index, reference, input) catch return false;
        const output = try self.functionOutputType(function);
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.sourceFor(reference.source, o),
            .ty = if (value.expected_type) |local| globalizer.globalType(o, local) else output,
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        self.stats.calls += 1;
        return true;
    }

    fn resolveField(self: *Resolver, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const source = globalizer.globalNode(o, value.value);
        const source_ty = self.graph.nodes.items[@intFromEnum(source)].ty orelse return false;
        const hit = types.findField(self.graph, source_ty, module.text(value.field_name)) orelse return false;
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(source)].source,
            .ty = hit.field.ty,
            .content = .{ .struct_field_access = .{
                .value = source,
                .field_name = try self.graph.addString(self.allocator, module.text(value.field_name)),
                .field_index = hit.index,
            } },
        };
        self.stats.fields += 1;
        return true;
    }

    fn resolveBinary(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !bool {
        const left = globalizer.globalNode(o, value.left);
        const right = globalizer.globalNode(o, value.right);
        const left_ty = self.graph.nodes.items[@intFromEnum(left)].ty orelse return false;
        const right_ty = self.graph.nodes.items[@intFromEnum(right)].ty orelse return false;
        const target = globalizer.globalNode(o, value.node);
        if (self.isBuiltinArithmetic(left_ty, right_ty)) {
            self.graph.nodes.items[@intFromEnum(target)] = .{
                .source = self.graph.nodes.items[@intFromEnum(left)].source,
                .ty = left_ty,
                .content = .{ .binary_operation = .{ .operator = value.operator, .left = left, .right = right } },
            };
            self.stats.operators += 1;
            return true;
        }
        if (value.operator != .addition) return false;
        const function = self.resolveOperator(module_index, .add, &.{ left_ty, right_ty }) catch return false;
        const input = try self.makeCallInput(function, &.{ left, right });
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(left)].source,
            .ty = try self.functionOutputType(function),
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        self.stats.operators += 1;
        return true;
    }

    fn resolveComparison(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !bool {
        const left = globalizer.globalNode(o, value.left);
        const right = globalizer.globalNode(o, value.right);
        const left_ty = self.graph.nodes.items[@intFromEnum(left)].ty orelse return false;
        const right_ty = self.graph.nodes.items[@intFromEnum(right)].ty orelse return false;
        const bool_ty = try self.builtin(.Bool);
        const target = globalizer.globalNode(o, value.node);
        if (self.isBuiltinComparable(left_ty, right_ty)) {
            self.graph.nodes.items[@intFromEnum(target)] = .{
                .source = self.graph.nodes.items[@intFromEnum(left)].source,
                .ty = bool_ty,
                .content = .{ .comparison = .{ .operator = value.operator, .left = left, .right = right } },
            };
            self.stats.operators += 1;
            return true;
        }
        const operator: callable.OperatorKind = switch (value.operator) {
            .equal => .equal,
            .not_equal => .not_equal,
            else => return false,
        };
        const function = self.resolveOperator(module_index, operator, &.{ left_ty, right_ty }) catch return false;
        const input = try self.makeCallInput(function, &.{ left, right });
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(left)].source,
            .ty = bool_ty,
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        self.stats.operators += 1;
        return true;
    }

    fn resolveIndex(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !bool {
        const collection = globalizer.globalNode(o, value.value);
        const index = globalizer.globalNode(o, value.index);
        const collection_ty = self.graph.nodes.items[@intFromEnum(collection)].ty orelse return false;
        if (types.arrayElement(self.graph, collection_ty)) |element_ty| {
            const target = globalizer.globalNode(o, value.node);
            self.graph.nodes.items[@intFromEnum(target)] = if (value.store_value) |local_store| .{
                .source = self.graph.nodes.items[@intFromEnum(collection)].source,
                .ty = element_ty,
                .content = .{ .array_store = .{
                    .array_ptr = collection,
                    .index = index,
                    .value = globalizer.globalNode(o, local_store),
                    .element_type = element_ty,
                    .array_type = collection_ty,
                } },
            } else .{
                .source = self.graph.nodes.items[@intFromEnum(collection)].source,
                .ty = element_ty,
                .content = .{ .array_index = .{
                    .array_ptr = collection,
                    .index = index,
                    .element_type = element_ty,
                    .array_type = collection_ty,
                } },
            };
            self.stats.indexes += 1;
            return true;
        }
        const operator: callable.OperatorKind = if (value.store_value == null) .get else .set;
        var operands: [3]global_sg.GlobalNodeId = undefined;
        operands[0] = collection;
        operands[1] = index;
        var count: usize = 2;
        if (value.store_value) |local| {
            operands[2] = globalizer.globalNode(o, local);
            count = 3;
        }
        var operand_types: [3]global_sg.GlobalTypeId = undefined;
        for (operands[0..count], 0..) |node, i| operand_types[i] = self.graph.nodes.items[@intFromEnum(node)].ty orelse return false;
        const function = self.resolveOperator(module_index, operator, operand_types[0..count]) catch return false;
        const input = try self.makeCallInput(function, operands[0..count]);
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(collection)].source,
            .ty = try self.functionOutputType(function),
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        self.stats.indexes += 1;
        return true;
    }

    fn callScore(self: *Resolver, function: global_sg.Function, input_type: ?global_sg.GlobalTypeId) ?u32 {
        if (input_type == null) return if (function.input.len == 0) 1 else null;
        const actual_fields = types.fields(self.graph, input_type.?) orelse return if (function.input.len == 1) 1 else null;
        if (actual_fields.len != function.input.len) return null;
        var score: u32 = 0;
        for (0..actual_fields.len) |i| {
            const actual = self.graph.fields.items[actual_fields.start + @as(u32, @intCast(i))].ty;
            const expected = self.graph.fields.items[function.input.start + @as(u32, @intCast(i))].ty;
            if (types.equal(self.graph, actual, expected)) score += 4
            else if (types.isBuiltin(self.graph, expected, .Any)) score += 1
            else return null;
        }
        return score;
    }

    fn structType(self: *Resolver, fields: global_sg.FieldRange) !global_sg.GlobalTypeId {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .structural => |shape| if (shape.fields.start == fields.start and shape.fields.len == fields.len)
                return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .structural = .{ .fields = fields } });
        return id;
    }

    fn builtin(self: *Resolver, builtin_type: primitives.BuiltinType) !global_sg.GlobalTypeId {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .builtin => |value| if (value == builtin_type) return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .builtin = builtin_type });
        return id;
    }

    fn isBuiltinArithmetic(self: *Resolver, a: global_sg.GlobalTypeId, b: global_sg.GlobalTypeId) bool {
        if (!types.equal(self.graph, a, b)) return false;
        return switch (self.graph.types.items[@intFromEnum(a)]) {
            .builtin => |value| switch (value) {
                .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64,
                .Float16, .Float32, .Float64 => true,
                else => false,
            },
            else => false,
        };
    }

    fn isBuiltinComparable(self: *Resolver, a: global_sg.GlobalTypeId, b: global_sg.GlobalTypeId) bool {
        if (!types.equal(self.graph, a, b)) return false;
        return switch (self.graph.types.items[@intFromEnum(a)]) {
            .builtin => |value| value != .Void and value != .Type and value != .Any,
            else => false,
        };
    }

    fn findModuleBySpelling(self: *Resolver, spelling: []const u8) !global_sg.GlobalModuleId {
        var found: ?global_sg.GlobalModuleId = null;
        for (self.graph.modules.items, 0..) |module, index| {
            const dir = self.graph.text(module.dir);
            if (!std.mem.eql(u8, dir, spelling) and !std.mem.eql(u8, std.fs.path.basename(dir), spelling)) continue;
            if (found != null) return error.AmbiguousModuleReference;
            found = @enumFromInt(@as(u32, @intCast(index)));
        }
        return found orelse error.UnknownModuleReference;
    }

    fn appendNode(self: *Resolver, source: primitives.SourceRef, ty: global_sg.GlobalTypeId, content: global_sg.Node.Content) !global_sg.GlobalNodeId {
        const id: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{ .source = source, .ty = ty, .content = content });
        return id;
    }

    fn sourceFor(self: *Resolver, source: primitives.SourceRef, o: globalizer.Offsets) primitives.SourceRef {
        _ = self;
        return .{ .file_index = o.file_base + source.file_index, .offset = source.offset };
    }

    fn syntheticSource(self: *Resolver) primitives.SourceRef {
        _ = self;
        return .{ .file_index = 0, .offset = 0 };
    }
};

test "global core resolver is graph-only" {
    try std.testing.expect(@sizeOf(Resolver) <= 96);
}
