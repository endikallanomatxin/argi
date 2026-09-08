const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const module_views = @import("module_semantic_views.zig");
const global_sg = @import("global_semantic_graph.zig");
const globalizer = @import("semantic_globalizer.zig");
const global_verify = @import("global_semantic_verify.zig");
const callable = @import("semantic_callable.zig");
const primitives = @import("semantic_primitives.zig");

pub const Stats = struct {
    external_types: u32 = 0,
    calls: u32 = 0,
    fields: u32 = 0,
    operators: u32 = 0,
    indexes: u32 = 0,
    remaining: u32 = 0,
};

pub const Result = struct {
    graph: global_sg.GlobalSemanticGraph,
    stats: Stats,
};

pub fn semantize(
    allocator: std.mem.Allocator,
    modules: []const module_sg.ModuleSemanticGraph,
) !Result {
    var relocation = try globalizer.relocate(allocator, modules, .allow_holes);
    errdefer relocation.deinit(allocator);

    var context = Context{
        .allocator = allocator,
        .modules = modules,
        .relocation = &relocation,
    };
    try context.resolveExternalTypes();
    try context.resolvePendingFixpoint();
    context.stats.remaining = @intCast(context.countRemaining());
    if (context.stats.remaining != 0) return error.UnsupportedGlobalSemantic;

    try context.materializeCompactSugarTypes();
    try global_verify.verifyGlobal(&relocation.graph);
    return .{ .graph = relocation.takeGraph(allocator), .stats = context.stats };
}

const Context = struct {
    allocator: std.mem.Allocator,
    modules: []const module_sg.ModuleSemanticGraph,
    relocation: *globalizer.Relocation,
    stats: Stats = .{},

    fn graph(self: *Context) *global_sg.GlobalSemanticGraph { return &self.relocation.graph; }

    fn resolveExternalTypes(self: *Context) !void {
        for (self.modules, 0..) |*module, module_index| {
            const offsets = self.relocation.offsets.items[module_index];
            for (0..module_views.typeCount(module)) |raw_type| {
                const local_id: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw_type)));
                const value = try module_views.typeView(module, local_id);
                const external = switch (value) {
                    .external => |id| id,
                    .resolved => continue,
                };
                const reference = module.semantic.external_refs.items[@intFromEnum(external)];
                if (reference.kind != .type) continue;
                const target = try self.resolveDeclaration(module_index, reference, &.{ .type, .abstract_type });
                const target_type = self.graph().declarations.items[@intFromEnum(target)].type_id orelse return error.ExternalTypeHasNoType;
                self.graph().types.items[@intFromEnum(globalizer.globalType(offsets, local_id))] = self.graph().types.items[@intFromEnum(target_type)];
                self.stats.external_types += 1;
            }
        }
    }

    fn resolvePendingFixpoint(self: *Context) !void {
        var resolved = try self.allocator.alloc(bool, self.totalPending());
        defer self.allocator.free(resolved);
        @memset(resolved, false);

        var changed = true;
        while (changed) {
            changed = false;
            var flat_index: usize = 0;
            for (self.modules, 0..) |*module, module_index| {
                const offsets = self.relocation.offsets.items[module_index];
                for (module.semantic.pending_operations.items) |operation| {
                    if (!resolved[flat_index]) {
                        if (try self.tryResolvePending(module_index, module, offsets, operation)) {
                            resolved[flat_index] = true;
                            changed = true;
                        }
                    }
                    flat_index += 1;
                }
            }
        }

        var unresolved: usize = 0;
        for (resolved) |done| if (!done) { unresolved += 1; };
        self.stats.remaining = @intCast(unresolved);
    }

    fn tryResolvePending(
        self: *Context,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        offsets: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !bool {
        return switch (operation) {
            .resolve_type => true,
            .resolve_call => |value| self.resolveCall(module_index, module, offsets, value),
            .resolve_field => |value| self.resolveField(module, offsets, value),
            .resolve_binary => |value| self.resolveBinary(module_index, module, offsets, value),
            .resolve_comparison => |value| self.resolveComparison(module_index, module, offsets, value),
            .resolve_index => |value| self.resolveIndex(module_index, module, offsets, value),
            .resolve_choice_literal,
            .resolve_choice_payload,
            .resolve_nullable_unwrap,
            .resolve_nullable_test,
            .resolve_error_propagation,
            .resolve_for_each,
            .resolve_match,
            .resolve_match_case,
            .resolve_defer,
            .resolve_keep,
            .resolve_expression,
            .resolve_abstract,
            .resolve_copy,
            .resolve_deinit,
            => false,
        };
    }

    fn resolveCall(self: *Context, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        const function_id = self.resolveFunction(module_index, reference, globalizer.globalNode(o, value.input)) catch |err| switch (err) {
            error.NoMatchingGlobalFunction, error.AmbiguousGlobalFunction => return false,
            else => return err,
        };
        const output_type = try self.functionOutputType(function_id);
        const target = globalizer.globalNode(o, value.node);
        self.graph().nodes.items[@intFromEnum(target)] = .{
            .source = self.globalSource(o, reference.source),
            .ty = value.expected_type orelse output_type,
            .content = .{ .function_call = .{
                .callee = function_id,
                .input = globalizer.globalNode(o, value.input),
            } },
        };
        self.stats.calls += 1;
        return true;
    }

    fn resolveField(self: *Context, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const source_node = globalizer.globalNode(o, value.value);
        const source_type = self.graph().nodes.items[@intFromEnum(source_node)].ty orelse return false;
        const name = module.text(value.field_name);
        const field = try self.findField(source_type, name) orelse return false;
        const target = globalizer.globalNode(o, value.node);
        self.graph().nodes.items[@intFromEnum(target)] = .{
            .source = self.graph().nodes.items[@intFromEnum(source_node)].source,
            .ty = field.ty,
            .content = .{ .struct_field_access = .{
                .value = source_node,
                .field_name = try self.graph().addString(self.allocator, name),
                .field_index = field.index,
            } },
        };
        self.stats.fields += 1;
        return true;
    }

    fn resolveBinary(self: *Context, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const left = globalizer.globalNode(o, value.left);
        const right = globalizer.globalNode(o, value.right);
        const left_ty = self.graph().nodes.items[@intFromEnum(left)].ty orelse return false;
        const right_ty = self.graph().nodes.items[@intFromEnum(right)].ty orelse return false;
        const target = globalizer.globalNode(o, value.node);
        if (self.isBuiltinArithmetic(left_ty, right_ty)) {
            self.graph().nodes.items[@intFromEnum(target)] = .{
                .source = self.graph().nodes.items[@intFromEnum(left)].source,
                .ty = left_ty,
                .content = .{ .binary_operation = .{ .operator = value.operator, .left = left, .right = right } },
            };
            self.stats.operators += 1;
            return true;
        }
        if (value.operator != .addition) return false;
        const function = self.resolveOperator(module_index, .add, &.{ left_ty, right_ty }) catch return false;
        const input = try self.makeCallInput(function, &.{ left, right });
        self.graph().nodes.items[@intFromEnum(target)] = .{
            .source = self.graph().nodes.items[@intFromEnum(left)].source,
            .ty = try self.functionOutputType(function),
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        _ = module;
        self.stats.operators += 1;
        return true;
    }

    fn resolveComparison(self: *Context, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const left = globalizer.globalNode(o, value.left);
        const right = globalizer.globalNode(o, value.right);
        const left_ty = self.graph().nodes.items[@intFromEnum(left)].ty orelse return false;
        const right_ty = self.graph().nodes.items[@intFromEnum(right)].ty orelse return false;
        const target = globalizer.globalNode(o, value.node);
        const bool_type = try self.builtinType(.Bool);
        if (self.isBuiltinComparable(left_ty, right_ty)) {
            self.graph().nodes.items[@intFromEnum(target)] = .{
                .source = self.graph().nodes.items[@intFromEnum(left)].source,
                .ty = bool_type,
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
        self.graph().nodes.items[@intFromEnum(target)] = .{
            .source = self.graph().nodes.items[@intFromEnum(left)].source,
            .ty = bool_type,
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        _ = module;
        self.stats.operators += 1;
        return true;
    }

    fn resolveIndex(self: *Context, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const collection = globalizer.globalNode(o, value.value);
        const index = globalizer.globalNode(o, value.index);
        const collection_ty = self.graph().nodes.items[@intFromEnum(collection)].ty orelse return false;
        if (self.arrayElement(collection_ty)) |element_ty| {
            const target = globalizer.globalNode(o, value.node);
            if (value.store_value) |local_store| {
                const store = globalizer.globalNode(o, local_store);
                self.graph().nodes.items[@intFromEnum(target)] = .{
                    .source = self.graph().nodes.items[@intFromEnum(collection)].source,
                    .ty = element_ty,
                    .content = .{ .array_store = .{
                        .array_ptr = collection, .index = index, .value = store,
                        .element_type = element_ty, .array_type = collection_ty,
                    } },
                };
            } else {
                self.graph().nodes.items[@intFromEnum(target)] = .{
                    .source = self.graph().nodes.items[@intFromEnum(collection)].source,
                    .ty = element_ty,
                    .content = .{ .array_index = .{
                        .array_ptr = collection, .index = index,
                        .element_type = element_ty, .array_type = collection_ty,
                    } },
                };
            }
            self.stats.indexes += 1;
            return true;
        }
        const operator: callable.OperatorKind = if (value.store_value == null) .get else .set;
        var operands: [3]global_sg.GlobalNodeId = undefined;
        operands[0] = collection;
        operands[1] = index;
        var count: usize = 2;
        if (value.store_value) |id| {
            operands[2] = globalizer.globalNode(o, id);
            count = 3;
        }
        var types: [3]global_sg.GlobalTypeId = undefined;
        for (operands[0..count], 0..) |operand, i| types[i] = self.graph().nodes.items[@intFromEnum(operand)].ty orelse return false;
        const function = self.resolveOperator(module_index, operator, types[0..count]) catch return false;
        const input = try self.makeCallInput(function, operands[0..count]);
        const target = globalizer.globalNode(o, value.node);
        self.graph().nodes.items[@intFromEnum(target)] = .{
            .source = self.graph().nodes.items[@intFromEnum(collection)].source,
            .ty = try self.functionOutputType(function),
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        _ = module;
        self.stats.indexes += 1;
        return true;
    }

    fn resolveDeclaration(
        self: *Context,
        current_module: usize,
        reference: module_entities.ExternalRef,
        kinds: []const primitives.DeclarationKind,
    ) !global_sg.GlobalDeclId {
        const module_filter = if (reference.module_path) |path| try self.findModuleBySpelling(current_module, self.modules[current_module].text(path)) else null;
        const name = self.modules[current_module].text(reference.name);
        var found: ?global_sg.GlobalDeclId = null;
        for (self.graph().declarations.items, 0..) |decl, raw| {
            const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
            if (module_filter) |wanted| if (self.graph().moduleForDeclaration(id).? != wanted) continue;
            var allowed = false;
            for (kinds) |kind| if (decl.kind == kind) { allowed = true; break; };
            if (!allowed or !std.mem.eql(u8, self.graph().text(decl.name), name)) continue;
            if (found != null) {
                if (reference.module_path == null) {
                    const owner = self.graph().moduleForDeclaration(id).?;
                    const current: global_sg.GlobalModuleId = @enumFromInt(@as(u32, @intCast(current_module)));
                    if (owner == current) { found = id; continue; }
                    if (self.graph().moduleForDeclaration(found.?).? == current) continue;
                }
                return error.AmbiguousGlobalDeclaration;
            }
            found = id;
        }
        return found orelse error.UnknownGlobalDeclaration;
    }

    fn resolveFunction(self: *Context, current_module: usize, reference: module_entities.ExternalRef, input_node: global_sg.GlobalNodeId) !global_sg.GlobalFunctionId {
        const module_filter = if (reference.module_path) |path| try self.findModuleBySpelling(current_module, self.modules[current_module].text(path)) else null;
        const name = self.modules[current_module].text(reference.name);
        const input_ty = self.graph().nodes.items[@intFromEnum(input_node)].ty;
        var best: ?global_sg.GlobalFunctionId = null;
        var best_score: u32 = 0;
        var tied = false;
        for (self.graph().functions.items, 0..) |function, raw| {
            const decl = self.graph().declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, self.graph().text(decl.name), name)) continue;
            if (module_filter) |wanted| if (self.graph().moduleForDeclaration(function.declaration).? != wanted) continue;
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

    fn resolveOperator(self: *Context, current_module: usize, operator: callable.OperatorKind, operand_types: []const global_sg.GlobalTypeId) !global_sg.GlobalFunctionId {
        var best: ?global_sg.GlobalFunctionId = null;
        var best_score: u32 = 0;
        var tied = false;
        for (self.graph().functions.items, 0..) |function, raw| {
            if (raw >= self.graph().function_operators.items.len or self.graph().function_operators.items[raw] != operator) continue;
            const field_start: usize = function.input.start;
            const field_len: usize = function.input.len;
            if (field_len != operand_types.len) continue;
            var score: u32 = 0;
            var compatible = true;
            for (operand_types, 0..) |ty, i| {
                const expected = self.graph().fields.items[field_start + i].ty;
                if (self.typesEqual(expected, ty)) score += 4 else if (self.isAny(expected)) score += 1 else { compatible = false; break; }
            }
            if (!compatible) continue;
            const owner = self.graph().moduleForDeclaration(function.declaration).?;
            if (@intFromEnum(owner) == current_module) score += 1;
            if (best == null or score > best_score) {
                best = @enumFromInt(@as(u32, @intCast(raw))); best_score = score; tied = false;
            } else if (score == best_score) tied = true;
        }
        if (best == null) return error.NoMatchingGlobalFunction;
        if (tied) return error.AmbiguousGlobalFunction;
        return best.?;
    }

    fn callScore(self: *Context, function: global_sg.Function, input_type: ?global_sg.GlobalTypeId) ?u32 {
        if (input_type == null) return if (function.input.len == 0) 1 else 0;
        const fields = self.fieldsForType(input_type.?) orelse return if (function.input.len == 1) 1 else null;
        if (fields.len != function.input.len) return null;
        var score: u32 = 0;
        for (0..fields.len) |i| {
            const actual = self.graph().fields.items[fields.start + @as(u32, @intCast(i))].ty;
            const expected = self.graph().fields.items[function.input.start + @as(u32, @intCast(i))].ty;
            if (self.typesEqual(actual, expected)) score += 4 else if (self.isAny(expected)) score += 1 else return null;
        }
        return score;
    }

    fn findField(self: *Context, ty: global_sg.GlobalTypeId, name: []const u8) !?struct { index: u32, ty: global_sg.GlobalTypeId } {
        const fields = self.fieldsForType(ty) orelse return null;
        for (0..fields.len) |offset| {
            const field = self.graph().fields.items[fields.start + @as(u32, @intCast(offset))];
            if (std.mem.eql(u8, self.graph().text(field.name), name)) return .{ .index = @intCast(offset), .ty = field.ty };
        }
        return null;
    }

    fn fieldsForType(self: *Context, ty: global_sg.GlobalTypeId) ?global_sg.FieldRange {
        return switch (self.graph().types.items[@intFromEnum(ty)]) {
            .structural => |shape| shape.fields,
            .declared => |decl| self.graph().declarations.items[@intFromEnum(decl)].struct_fields,
            .generic => blk: {
                for (self.graph().generic_instances.items) |instance| if (instance.type_id == ty) switch (instance.shape) {
                    .structure => |shape| break :blk shape.fields,
                    .alias => |target| break :blk self.fieldsForType(target),
                    else => {},
                };
                break :blk null;
            },
            else => null,
        };
    }

    fn arrayElement(self: *Context, ty: global_sg.GlobalTypeId) ?global_sg.GlobalTypeId {
        return switch (self.graph().types.items[@intFromEnum(ty)]) {
            .array => |array| array.element,
            .generic => blk: {
                for (self.graph().generic_instances.items) |instance| if (instance.type_id == ty) switch (instance.shape) {
                    .array => |shape| break :blk shape.element,
                    .alias => |target| break :blk self.arrayElement(target),
                    else => {},
                };
                break :blk null;
            },
            else => null,
        };
    }

    fn makeCallInput(self: *Context, function_id: global_sg.GlobalFunctionId, nodes: []const global_sg.GlobalNodeId) !global_sg.GlobalNodeId {
        const function = self.graph().functions.items[@intFromEnum(function_id)];
        if (nodes.len != function.input.len) return error.InvalidCallInputArity;
        const value_start: u32 = @intCast(self.graph().value_fields.items.len);
        for (nodes, 0..) |node, index| {
            const field = self.graph().fields.items[function.input.start + @as(u32, @intCast(index))];
            try self.graph().value_fields.append(self.allocator, .{ .name = field.name, .value = node });
        }
        const ty = try self.structType(function.input);
        const source = if (nodes.len != 0) self.graph().nodes.items[@intFromEnum(nodes[0])].source else primitives.SourceRef{ .file_index = 0, .offset = 0 };
        const node_id: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph().nodes.items.len)));
        try self.graph().nodes.append(self.allocator, .{
            .source = source, .ty = ty,
            .content = .{ .struct_value_literal = .{
                .fields = .{ .start = value_start, .len = @intCast(nodes.len) }, .ty = ty,
            } },
        });
        return node_id;
    }

    fn structType(self: *Context, fields: global_sg.FieldRange) !global_sg.GlobalTypeId {
        for (self.graph().types.items, 0..) |ty, raw| switch (ty) {
            .structural => |shape| if (shape.fields.start == fields.start and shape.fields.len == fields.len)
                return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph().types.items.len)));
        try self.graph().types.append(self.allocator, .{ .structural = .{ .fields = fields } });
        return id;
    }

    fn functionOutputType(self: *Context, id: global_sg.GlobalFunctionId) !global_sg.GlobalTypeId {
        const function = self.graph().functions.items[@intFromEnum(id)];
        if (function.output.len == 0) return self.builtinType(.Void);
        if (function.output.len == 1) return self.graph().fields.items[function.output.start].ty;
        return self.structType(function.output);
    }

    fn builtinType(self: *Context, builtin: primitives.BuiltinType) !global_sg.GlobalTypeId {
        for (self.graph().types.items, 0..) |ty, raw| switch (ty) {
            .builtin => |candidate| if (candidate == builtin) return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph().types.items.len)));
        try self.graph().types.append(self.allocator, .{ .builtin = builtin });
        return id;
    }

    fn typesEqual(self: *Context, a: global_sg.GlobalTypeId, b: global_sg.GlobalTypeId) bool {
        if (a == b) return true;
        const left = self.graph().types.items[@intFromEnum(a)];
        const right = self.graph().types.items[@intFromEnum(b)];
        return switch (left) {
            .builtin => |x| switch (right) { .builtin => |y| x == y, else => false },
            .declared => |x| switch (right) { .declared => |y| x == y, else => false },
            .pointer => |x| switch (right) { .pointer => |y| x.mutability == y.mutability and self.typesEqual(x.child, y.child), else => false },
            .array => |x| switch (right) { .array => |y| x.length == y.length and self.typesEqual(x.element, y.element), else => false },
            else => false,
        };
    }

    fn isAny(self: *Context, id: global_sg.GlobalTypeId) bool {
        return switch (self.graph().types.items[@intFromEnum(id)]) { .builtin => |value| value == .Any, else => false };
    }

    fn isBuiltinArithmetic(self: *Context, a: global_sg.GlobalTypeId, b: global_sg.GlobalTypeId) bool {
        if (!self.typesEqual(a, b)) return false;
        return switch (self.graph().types.items[@intFromEnum(a)]) {
            .builtin => |value| switch (value) {
                .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64, .Float16, .Float32, .Float64 => true,
                else => false,
            },
            else => false,
        };
    }

    fn isBuiltinComparable(self: *Context, a: global_sg.GlobalTypeId, b: global_sg.GlobalTypeId) bool {
        if (!self.typesEqual(a, b)) return false;
        return switch (self.graph().types.items[@intFromEnum(a)]) {
            .builtin => |value| value != .Void and value != .Type and value != .Any,
            else => false,
        };
    }

    fn findModuleBySpelling(self: *Context, current_module: usize, spelling: []const u8) !global_sg.GlobalModuleId {
        _ = current_module;
        var found: ?global_sg.GlobalModuleId = null;
        for (self.graph().modules.items, 0..) |module, index| {
            const dir = self.graph().text(module.dir);
            const base = std.fs.path.basename(dir);
            if (!std.mem.eql(u8, dir, spelling) and !std.mem.eql(u8, base, spelling)) continue;
            if (found != null) return error.AmbiguousModuleReference;
            found = @enumFromInt(@as(u32, @intCast(index)));
        }
        return found orelse error.UnknownModuleReference;
    }

    fn materializeCompactSugarTypes(self: *Context) !void {
        // Nullable/Errable lowering is implemented by the next GlobalSema layer.
        // Do not silently allow their compact ModuleSema forms into Safety.
        for (self.graph().types.items) |ty| switch (ty) {
            .nullable, .inferred_errable => return error.UnmaterializedGlobalSugarType,
            else => {},
        };
    }

    fn globalSource(self: *Context, o: globalizer.Offsets, source: primitives.SourceRef) primitives.SourceRef {
        _ = self;
        return .{ .file_index = o.file_base + source.file_index, .offset = source.offset };
    }

    fn totalPending(self: *Context) usize {
        var total: usize = 0;
        for (self.modules) |module| total += module.semantic.pending_operations.items.len;
        return total;
    }

    fn countRemaining(self: *Context) usize { return self.stats.remaining; }
};

test "global semantizer accepts an empty program" {
    const allocator = std.testing.allocator;
    var result = try semantize(allocator, &.{});
    defer result.graph.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.graph.nodes.items.len);
}
