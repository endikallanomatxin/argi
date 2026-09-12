const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const module_views = @import("../module/views.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const resolution = @import("resolution.zig");
const types = @import("types.zig");
const callable = @import("../primitives/callable.zig");
const primitives = @import("../primitives/schema.zig");

pub const Stats = struct {
    external_types: u32 = 0,
    calls: u32 = 0,
    fields: u32 = 0,
    operators: u32 = 0,
    indexes: u32 = 0,
    dereferences: u32 = 0,
    binding_types: u32 = 0,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    stats: Stats = .{},
    abstract_context: ?*anyopaque = null,
    abstract_compatible: ?*const fn (*anyopaque, global_sg.GlobalTypeId, global_sg.GlobalTypeId) bool = null,

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
                const target = self.resolveDeclaration(module_index, reference, &.{ .type, .abstract_type }) catch continue;
                const target_type = self.graph.declarations.items[@intFromEnum(target)].type_id orelse continue;
                self.graph.types.items[@intFromEnum(globalizer.globalType(o, local_id))] = .{ .declared = target };
                _ = target_type;
                self.stats.external_types += 1;
            }
        }
    }

    pub fn materializeDereferences(self: *Resolver) bool {
        var changed = false;
        for (self.graph.nodes.items) |*node| switch (node.content) {
            .dereference => |*dereference| {
                const pointer_type = self.graph.nodes.items[@intFromEnum(dereference.pointer)].ty orelse continue;
                const child = switch (self.graph.types.items[@intFromEnum(pointer_type)]) {
                    .pointer => |pointer| pointer.child,
                    else => continue,
                };
                if (node.ty != null and types.equal(self.graph, node.ty.?, child) and types.equal(self.graph, dereference.pointer_type, pointer_type)) continue;
                node.ty = child;
                dereference.ty = child;
                dereference.pointer_type = pointer_type;
                self.stats.dereferences += 1;
                changed = true;
            },
            else => {},
        };
        return changed;
    }

    pub fn materializeAddresses(self: *Resolver) !bool {
        var changed = false;
        for (self.graph.nodes.items) |*node| switch (node.content) {
            .address_of => |value| {
                const child = self.graph.nodes.items[@intFromEnum(value)].ty orelse continue;
                const mutability = if (node.ty) |old| switch (self.graph.types.items[@intFromEnum(old)]) {
                    .pointer => |pointer| pointer.mutability,
                    else => continue,
                } else continue;
                const pointer_type = try self.pointerType(child, mutability);
                if (node.ty != null and types.equal(self.graph, node.ty.?, pointer_type)) continue;
                node.ty = pointer_type;
                changed = true;
            },
            else => {},
        };
        return changed;
    }

    pub fn materializeBindingTypes(self: *Resolver) bool {
        var changed = false;
        for (self.graph.bindings.items, 0..) |*binding, raw| {
            const id: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(raw)));
            if (!self.graph.isBindingTypeUnresolved(id)) continue;
            const initialization = binding.initialization orelse continue;
            const inferred = self.graph.nodes.items[@intFromEnum(initialization)].ty orelse continue;
            if (self.graph.isTypeUnresolved(inferred)) continue;
            binding.ty = inferred;
            self.stats.binding_types += 1;
            changed = true;
        }
        for (self.graph.nodes.items) |*node| switch (node.content) {
            .binding_use => |binding_id| {
                if (self.graph.isBindingTypeUnresolved(binding_id)) continue;
                const inferred = self.graph.bindings.items[@intFromEnum(binding_id)].ty;
                if (node.ty != null and types.equal(self.graph, node.ty.?, inferred)) continue;
                node.ty = inferred;
                changed = true;
            },
            .move_value => |value| {
                const inferred = self.graph.nodes.items[@intFromEnum(value)].ty orelse continue;
                if (node.ty != null and types.equal(self.graph, node.ty.?, inferred)) continue;
                node.ty = inferred;
                changed = true;
            },
            .binary_operation => |operation| {
                var left_ty = self.graph.nodes.items[@intFromEnum(operation.left)].ty orelse continue;
                var right_ty = self.graph.nodes.items[@intFromEnum(operation.right)].ty orelse continue;
                self.coerceIntegerPair(operation.left, &left_ty, operation.right, &right_ty);
                if (!self.isBuiltinArithmetic(left_ty, right_ty)) continue;
                if (node.ty != null and types.equal(self.graph, node.ty.?, left_ty)) continue;
                node.ty = left_ty;
                changed = true;
            },
            else => {},
        };
        return changed;
    }

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        return switch (operation) {
            .resolve_type => |value| try self.resolveTypeHole(module_index, module, o, value),
            .resolve_call => |value| try self.resolveCall(module_index, module, o, value),
            .resolve_field => |value| resolution.Result.fromBool(try self.resolveField(module, o, value)),
            .resolve_binary => |value| resolution.Result.fromBool(try self.resolveBinary(module_index, o, value)),
            .resolve_comparison => |value| resolution.Result.fromBool(try self.resolveComparison(module_index, o, value)),
            .resolve_index => |value| try self.resolveIndex(module_index, o, value),
            .resolve_dereference => |value| try self.resolveDereference(o, value),
            .resolve_address => |value| try self.resolveAddress(o, value),
            else => .not_applicable,
        };
    }

    pub fn resolveDeclaration(
        self: *Resolver,
        current_module: usize,
        reference: module_entities.ExternalRef,
        kinds: []const primitives.DeclarationKind,
    ) !global_sg.GlobalDeclId {
        const module_filter = if (reference.module_path) |path|
            try self.findModuleForQualifier(current_module, self.modules[current_module].text(path))
        else
            null;
        const name = self.modules[current_module].text(reference.name);
        var found: ?global_sg.GlobalDeclId = null;
        for (self.graph.declarations.items, 0..) |decl, raw| {
            const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
            if (!self.declarationVisible(current_module, id, module_filter)) continue;
            var allowed = false;
            for (kinds) |kind| if (decl.kind == kind) {
                allowed = true;
                break;
            };
            if (!allowed or !std.mem.eql(u8, self.graph.text(decl.name), name)) continue;
            if (found) |previous| {
                if (reference.module_path == null) {
                    const current: global_sg.GlobalModuleId = @enumFromInt(@as(u32, @intCast(current_module)));
                    const owner = self.graph.moduleForDeclaration(id).?;
                    const previous_owner = self.graph.moduleForDeclaration(previous).?;
                    if (owner == current and previous_owner != current) {
                        found = id;
                        continue;
                    }
                    if (previous_owner == current and owner != current) continue;
                }
                return error.AmbiguousGlobalDeclaration;
            }
            found = id;
        }
        return found orelse error.UnknownGlobalDeclaration;
    }

    pub const FunctionMatch = union(enum) {
        no_match,
        deferred,
        function: global_sg.GlobalFunctionId,
    };

    pub fn matchFunctionByName(
        self: *Resolver,
        current_module: usize,
        reference: module_entities.ExternalRef,
        input_node: global_sg.GlobalNodeId,
    ) !FunctionMatch {
        const module_filter = if (reference.module_path) |path|
            try self.findModuleForQualifier(current_module, self.modules[current_module].text(path))
        else
            null;
        const name = self.modules[current_module].text(reference.name);
        var best: ?global_sg.GlobalFunctionId = null;
        var best_score: u32 = 0;
        var tied = false;
        var saw_deferred = false;
        for (self.graph.functions.items, 0..) |function, raw| {
            if (function.flags.is_abstract_dispatch) continue;
            const decl = self.graph.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, self.graph.text(decl.name), name)) continue;
            if (!self.declarationVisible(current_module, function.declaration, module_filter)) continue;
            const score = switch (self.matchCallInput(function.input, input_node)) {
                .no_match => continue,
                .deferred => {
                    saw_deferred = true;
                    continue;
                },
                .score => |score| score,
            };
            if (best == null or score > best_score) {
                best = @enumFromInt(@as(u32, @intCast(raw)));
                best_score = score;
                tied = false;
            } else if (score == best_score) tied = true;
        }
        if (best) |function| {
            if (tied) return error.AmbiguousGlobalFunction;
            return .{ .function = function };
        }
        if (saw_deferred) return .deferred;
        return .no_match;
    }

    pub fn resolveFunctionByName(
        self: *Resolver,
        current_module: usize,
        reference: module_entities.ExternalRef,
        input_node: global_sg.GlobalNodeId,
    ) !global_sg.GlobalFunctionId {
        return switch (try self.matchFunctionByName(current_module, reference, input_node)) {
            .function => |function| function,
            .no_match => error.NoMatchingGlobalFunction,
            .deferred => error.DeferredGlobalFunction,
        };
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
                if (types.equal(self.graph, expected, actual)) score += 4 else if (types.isBuiltin(self.graph, expected, .Any)) score += 1 else {
                    compatible = false;
                    break;
                }
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

    /// Global storage does not imply global visibility. Unqualified lookup sees
    /// the current module and the implicit core; explicit imports select one
    /// module and still respect private declaration names.
    pub fn declarationVisible(self: *const Resolver, current_module: usize, declaration: global_sg.GlobalDeclId, qualified_module: ?global_sg.GlobalModuleId) bool {
        const owner = self.graph.moduleForDeclaration(declaration) orelse return false;
        const own_module = @intFromEnum(owner) == current_module;
        const name = self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name);
        if (!own_module and std.mem.startsWith(u8, name, "_")) return false;
        if (qualified_module) |wanted| return owner == wanted;
        return own_module or self.graph.modules.items[@intFromEnum(owner)].is_bundled_core;
    }

    pub fn functionOutputType(self: *Resolver, id: global_sg.GlobalFunctionId) !global_sg.GlobalTypeId {
        const function = self.graph.functions.items[@intFromEnum(id)];
        return self.outputTypeForFields(function.output);
    }

    pub fn outputTypeForFields(self: *Resolver, fields: global_sg.FieldRange) !global_sg.GlobalTypeId {
        if (fields.len == 0) return self.builtin(.Void);
        if (fields.len == 1) return self.graph.fields.items[fields.start].ty;
        return self.structType(fields);
    }

    pub fn isUnpackedOutputField(self: *const Resolver, node: global_sg.GlobalNodeId, name: []const u8) bool {
        const function_id = switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .function_call => |call| call.callee,
            else => return false,
        };
        const output = self.graph.functions.items[@intFromEnum(function_id)].output;
        if (output.len != 1) return false;
        return std.mem.eql(u8, self.graph.text(self.graph.fields.items[output.start].name), name);
    }

    pub fn makeCallInput(self: *Resolver, function_id: global_sg.GlobalFunctionId, nodes: []const global_sg.GlobalNodeId) !global_sg.GlobalNodeId {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        if (nodes.len != function.input.len) return error.InvalidCallInputArity;
        const start: u32 = @intCast(self.graph.value_fields.items.len);
        for (nodes, 0..) |node, index| {
            const field = self.graph.fields.items[function.input.start + @as(u32, @intCast(index))].ty;
            _ = field;
            const source_field = self.graph.fields.items[function.input.start + @as(u32, @intCast(index))];
            try self.graph.value_fields.append(self.allocator, .{ .name = source_field.name, .value = node });
        }
        const ty = try self.structType(function.input);
        const source = if (nodes.len != 0) self.graph.nodes.items[@intFromEnum(nodes[0])].source else self.syntheticSource();
        return self.appendNode(source, ty, .{ .struct_value_literal = .{
            .fields = .{ .start = start, .len = @intCast(nodes.len) },
            .ty = ty,
        } });
    }

    fn resolveTypeHole(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.external)];
        if (reference.generic_arguments != null) return .not_applicable;
        const target = self.resolveDeclaration(module_index, reference, &.{ .type, .abstract_type }) catch return .deferred;
        self.graph.types.items[@intFromEnum(globalizer.globalType(o, value.destination))] = .{ .declared = target };
        self.stats.external_types += 1;
        return .resolved;
    }

    fn resolveCall(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        if (reference.generic_arguments != null) return .not_applicable;
        const input = globalizer.globalNode(o, value.input);
        if (reference.module_path == null and std.mem.eql(u8, module.text(reference.name), "size_of")) {
            const node = (try self.makeSizeOf(input, self.sourceFor(reference.source, o))) orelse return .deferred;
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
            self.stats.calls += 1;
            return .resolved;
        }
        if (reference.module_path == null and std.mem.eql(u8, module.text(reference.name), "Void")) {
            const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
                .struct_value_literal => |item| item,
                else => return .deferred,
            };
            if (literal.fields.len != 0) return .deferred;
            const void_ty = try self.builtin(.Void);
            const target = globalizer.globalNode(o, value.node);
            self.graph.nodes.items[@intFromEnum(target)] = .{
                .source = self.sourceFor(reference.source, o),
                .ty = void_ty,
                .content = .{ .struct_value_literal = .{
                    .fields = .{ .start = @intCast(self.graph.value_fields.items.len), .len = 0 },
                    .ty = void_ty,
                } },
            };
            self.stats.calls += 1;
            return .resolved;
        }
        const function = switch (try self.matchFunctionByName(module_index, reference, input)) {
            .no_match => return .not_applicable,
            .deferred => return .deferred,
            .function => |function| function,
        };
        if (!try self.completeCallInput(function, input)) return .deferred;
        const output = try self.functionOutputType(function);
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.sourceFor(reference.source, o),
            .ty = if (value.expected_type) |local| globalizer.globalType(o, local) else output,
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        self.stats.calls += 1;
        return .resolved;
    }

    fn makeSizeOf(self: *Resolver, input: global_sg.GlobalNodeId, source: primitives.SourceRef) !?global_sg.Node {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        var measured: ?global_sg.GlobalTypeId = null;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            if (!std.mem.eql(u8, self.graph.text(field.name), "type")) continue;
            measured = switch (self.graph.nodes.items[@intFromEnum(field.value)].content) {
                .type_literal => |ty| ty,
                else => return null,
            };
            break;
        }
        const size = types.sizeOf(self.graph, measured orelse return null) catch return null;
        return .{
            .source = source,
            .ty = try self.builtin(.UIntNative),
            .content = .{ .int_literal = std.math.cast(i64, size) orelse return error.TypeSizeOverflow },
        };
    }

    fn resolveField(self: *Resolver, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const source = globalizer.globalNode(o, value.value);
        const source_ty = self.graph.nodes.items[@intFromEnum(source)].ty orelse return false;
        const target = globalizer.globalNode(o, value.node);
        const field_name = module.text(value.field_name);
        if (self.isUnpackedOutputField(source, field_name)) {
            self.graph.nodes.items[@intFromEnum(target)] = self.graph.nodes.items[@intFromEnum(source)];
            self.stats.fields += 1;
            return true;
        }
        const hit = types.findField(self.graph, source_ty, field_name) orelse return false;
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

    fn resolveDereference(self: *Resolver, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const pointer = globalizer.globalNode(o, value.pointer);
        const pointer_type = self.graph.nodes.items[@intFromEnum(pointer)].ty orelse return .deferred;
        if (self.graph.isTypeUnresolved(pointer_type)) return .deferred;
        const child = switch (self.graph.types.items[@intFromEnum(pointer_type)]) {
            .pointer => |pointer_value| pointer_value.child,
            else => return .deferred,
        };
        if (self.graph.isTypeUnresolved(child)) return .deferred;
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(pointer)].source,
            .ty = child,
            .content = .{ .dereference = .{
                .pointer = pointer,
                .ty = child,
                .pointer_type = pointer_type,
            } },
        };
        self.stats.dereferences += 1;
        return .resolved;
    }

    fn resolveAddress(self: *Resolver, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const child_node = globalizer.globalNode(o, value.value);
        const child = self.graph.nodes.items[@intFromEnum(child_node)].ty orelse return .deferred;
        if (self.graph.isTypeUnresolved(child)) return .deferred;
        const pointer_type = try self.pointerType(child, value.mutability);
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(child_node)].source,
            .ty = pointer_type,
            .content = .{ .address_of = child_node },
        };
        return .resolved;
    }

    fn resolveBinary(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !bool {
        const left = globalizer.globalNode(o, value.left);
        const right = globalizer.globalNode(o, value.right);
        var left_ty = self.graph.nodes.items[@intFromEnum(left)].ty orelse return false;
        var right_ty = self.graph.nodes.items[@intFromEnum(right)].ty orelse return false;
        self.coerceIntegerPair(left, &left_ty, right, &right_ty);
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
        var left_ty = self.graph.nodes.items[@intFromEnum(left)].ty orelse return false;
        var right_ty = self.graph.nodes.items[@intFromEnum(right)].ty orelse return false;
        self.coerceIntegerPair(left, &left_ty, right, &right_ty);
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

    fn resolveIndex(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const collection = globalizer.globalNode(o, value.value);
        const index = globalizer.globalNode(o, value.index);
        const collection_ty = self.graph.nodes.items[@intFromEnum(collection)].ty orelse return .deferred;
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
            return .resolved;
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
        for (operands[0..count], 0..) |node, i| operand_types[i] = self.graph.nodes.items[@intFromEnum(node)].ty orelse return .deferred;
        const function = self.resolveOperator(module_index, operator, operand_types[0..count]) catch switch (self.graph.types.items[@intFromEnum(collection_ty)]) {
            .generic => return .not_applicable,
            else => return .deferred,
        };
        const input = try self.makeCallInput(function, operands[0..count]);
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(collection)].source,
            .ty = try self.functionOutputType(function),
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        self.stats.indexes += 1;
        return .resolved;
    }

    pub const CallInputMatch = union(enum) {
        no_match,
        deferred,
        score: u32,
    };

    pub fn matchCallInput(self: *Resolver, expected_fields: global_sg.FieldRange, input_node: global_sg.GlobalNodeId) CallInputMatch {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input_node)].content) {
            .struct_value_literal => |value| value,
            else => return .no_match,
        };
        if (literal.fields.len > expected_fields.len) return .no_match;
        var score: u32 = 0;
        for (0..expected_fields.len) |expected_offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(expected_offset))];
            const supplied = self.callArgument(literal, expected_offset, expected.name);
            if (supplied) |node| {
                if (self.graph.isTypeUnresolved(expected.ty)) return .deferred;
                const supplied_node = self.graph.nodes.items[@intFromEnum(node)];
                if (supplied_node.ty) |actual| {
                    if (self.graph.isTypeUnresolved(actual)) return .deferred;
                    if (types.equal(self.graph, actual, expected.ty)) score += 4 else if (self.callTypesCompatible(actual, expected.ty)) score += 3 else if (types.isBuiltin(self.graph, expected.ty, .Any)) score += 1 else if (self.contextualLiteralFits(node, expected.ty)) score += 3 else return .no_match;
                } else switch (supplied_node.content) {
                    .string_literal => {
                        if (self.contextualLiteralFits(node, expected.ty))
                            score += 3
                        else
                            return .no_match;
                    },
                    else => return .deferred,
                }
            } else if (expected.default_value == null) return .no_match;
        }
        return .{ .score = score };
    }

    pub fn scoreCallInput(self: *Resolver, expected_fields: global_sg.FieldRange, input_node: global_sg.GlobalNodeId) ?u32 {
        return switch (self.matchCallInput(expected_fields, input_node)) {
            .score => |score| score,
            .no_match, .deferred => null,
        };
    }

    pub fn callTypesCompatible(self: *const Resolver, actual: global_sg.GlobalTypeId, expected: global_sg.GlobalTypeId) bool {
        const actual_pointer = switch (self.graph.types.items[@intFromEnum(actual)]) {
            .pointer => |pointer| pointer,
            else => return false,
        };
        const expected_pointer = switch (self.graph.types.items[@intFromEnum(expected)]) {
            .pointer => |pointer| pointer,
            else => return false,
        };
        if (expected_pointer.mutability == .read_write and actual_pointer.mutability != .read_write) return false;
        if (types.equal(self.graph, actual_pointer.child, expected_pointer.child)) return true;
        if (self.abstract_context) |context| {
            if (self.abstract_compatible) |compatible|
                if (compatible(context, actual_pointer.child, expected_pointer.child)) return true;
        }
        return switch (self.graph.types.items[@intFromEnum(actual_pointer.child)]) {
            .virtual => |abstract_type| types.equal(self.graph, abstract_type, expected_pointer.child),
            else => false,
        };
    }

    fn callArgument(self: *const Resolver, literal: anytype, expected_offset: usize, expected_name: primitives.StringRange) ?global_sg.GlobalNodeId {
        for (0..literal.fields.len) |supplied_offset| {
            const supplied = self.graph.value_fields.items[literal.fields.start + @as(u32, @intCast(supplied_offset))];
            if (supplied_offset < literal.dispatch_prefix_positional_count or self.graph.text(supplied.name).len == 0) {
                if (supplied_offset == expected_offset) return supplied.value;
            } else if (std.mem.eql(u8, self.graph.text(supplied.name), self.graph.text(expected_name))) return supplied.value;
        }
        return null;
    }

    fn completeCallInput(self: *Resolver, function_id: global_sg.GlobalFunctionId, input_node: global_sg.GlobalNodeId) !bool {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        return self.completeCallInputFields(function.input, input_node);
    }

    pub fn completeCallInputFields(self: *Resolver, expected_fields: global_sg.FieldRange, input_node: global_sg.GlobalNodeId) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input_node)].content) {
            .struct_value_literal => |value| value,
            else => return false,
        };
        const start: u32 = @intCast(self.graph.value_fields.items.len);
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            const node = self.callArgument(literal, offset, expected.name) orelse expected.default_value orelse return false;
            _ = self.coerceContextualLiteral(node, expected.ty);
            try self.graph.value_fields.append(self.allocator, .{ .name = expected.name, .value = node });
        }
        const ty = try self.structType(expected_fields);
        self.graph.nodes.items[@intFromEnum(input_node)].ty = ty;
        self.graph.nodes.items[@intFromEnum(input_node)].content.struct_value_literal = .{
            .fields = .{ .start = start, .len = expected_fields.len },
            .ty = ty,
        };
        return true;
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

    fn pointerType(self: *Resolver, child: global_sg.GlobalTypeId, mutability: primitives.PointerMutability) !global_sg.GlobalTypeId {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .pointer => |pointer| if (pointer.mutability == mutability and types.equal(self.graph, pointer.child, child))
                return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .pointer = .{ .child = child, .mutability = mutability } });
        return id;
    }

    fn isBuiltinArithmetic(self: *Resolver, a: global_sg.GlobalTypeId, b: global_sg.GlobalTypeId) bool {
        if (!types.equal(self.graph, a, b)) return false;
        return switch (self.graph.types.items[@intFromEnum(a)]) {
            .builtin => |value| switch (value) {
                .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64, .Float16, .Float32, .Float64 => true,
                else => false,
            },
            else => false,
        };
    }

    fn coerceIntegerPair(
        self: *Resolver,
        left: global_sg.GlobalNodeId,
        left_ty: *global_sg.GlobalTypeId,
        right: global_sg.GlobalNodeId,
        right_ty: *global_sg.GlobalTypeId,
    ) void {
        if (types.equal(self.graph, left_ty.*, right_ty.*)) return;
        if (self.coerceIntegerLiteral(left, right_ty.*)) {
            left_ty.* = right_ty.*;
        } else if (self.coerceIntegerLiteral(right, left_ty.*)) {
            right_ty.* = left_ty.*;
        }
    }

    fn coerceIntegerLiteral(self: *Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        if (!self.integerLiteralFits(node, target)) return false;
        self.graph.nodes.items[@intFromEnum(node)].ty = target;
        return true;
    }

    fn contextualLiteralFits(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        if (self.integerLiteralFits(node, target)) return true;
        switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .string_literal => return switch (self.graph.types.items[@intFromEnum(target)]) {
                .pointer => |pointer| pointer.mutability == .read_only and types.isBuiltin(self.graph, pointer.child, .Char),
                else => false,
            },
            .struct_value_literal => |literal| return self.contextualStructLiteralFits(literal, target),
            else => return false,
        }
    }

    fn contextualStructLiteralFits(self: *const Resolver, literal: anytype, target: global_sg.GlobalTypeId) bool {
        const expected_fields = types.fields(self.graph, target) orelse return false;
        if (literal.fields.len > expected_fields.len) return false;
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            const supplied = self.callArgument(literal, offset, expected.name) orelse {
                if (expected.default_value == null) return false;
                continue;
            };
            const supplied_node = self.graph.nodes.items[@intFromEnum(supplied)];
            if (supplied_node.ty) |actual| {
                if (types.equal(self.graph, actual, expected.ty) or self.callTypesCompatible(actual, expected.ty) or
                    self.contextualLiteralFits(supplied, expected.ty)) continue;
            } else if (self.contextualLiteralFits(supplied, expected.ty)) continue;
            return false;
        }
        return true;
    }

    fn coerceContextualLiteral(self: *Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        if (!self.contextualLiteralFits(node, target)) return false;
        self.graph.nodes.items[@intFromEnum(node)].ty = target;
        return true;
    }

    pub fn coerceContextualValue(self: *Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        if (self.coerceContextualLiteral(node, target)) return true;
        const current = self.graph.nodes.items[@intFromEnum(node)].ty;
        const literal = switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .struct_value_literal => |value| value,
            else => {
                if (current == null or types.isBuiltin(self.graph, current.?, .Any)) {
                    self.graph.nodes.items[@intFromEnum(node)].ty = target;
                    return true;
                }
                return false;
            },
        };
        const expected_fields = types.fields(self.graph, target) orelse return false;
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            const actual = self.callArgument(literal, offset, expected.name) orelse continue;
            _ = self.coerceContextualValue(actual, expected.ty);
        }
        self.graph.nodes.items[@intFromEnum(node)].ty = target;
        self.graph.nodes.items[@intFromEnum(node)].content.struct_value_literal.ty = target;
        return true;
    }

    fn integerLiteralFits(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        const value = switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .int_literal => |number| number,
            else => return false,
        };
        const fits = switch (self.graph.types.items[@intFromEnum(target)]) {
            .builtin => |builtin_type| switch (builtin_type) {
                .Int8 => value >= std.math.minInt(i8) and value <= std.math.maxInt(i8),
                .Int16 => value >= std.math.minInt(i16) and value <= std.math.maxInt(i16),
                .Int32 => value >= std.math.minInt(i32) and value <= std.math.maxInt(i32),
                .Int64 => true,
                .UIntNative => value >= 0,
                .UInt8 => value >= 0 and value <= std.math.maxInt(u8),
                .UInt16 => value >= 0 and value <= std.math.maxInt(u16),
                .UInt32 => value >= 0 and value <= std.math.maxInt(u32),
                .UInt64 => value >= 0,
                else => false,
            },
            else => false,
        };
        return fits;
    }

    fn isBuiltinComparable(self: *Resolver, a: global_sg.GlobalTypeId, b: global_sg.GlobalTypeId) bool {
        if (!types.equal(self.graph, a, b)) return false;
        return switch (self.graph.types.items[@intFromEnum(a)]) {
            .builtin => |value| value != .Void and value != .Type and value != .Any,
            else => false,
        };
    }

    /// Resolve a source qualifier through the module aliases linked before
    /// semantic resolution. Paths are no longer semantic identity here.
    pub fn findModuleForQualifier(self: *Resolver, current_module: usize, qualifier: []const u8) !global_sg.GlobalModuleId {
        var found: ?global_sg.GlobalModuleId = null;
        const current: global_sg.GlobalModuleId = @enumFromInt(@as(u32, @intCast(current_module)));
        for (self.graph.module_aliases.items) |alias| {
            if (alias.owner != current) continue;
            const declaration = self.graph.declarations.items[@intFromEnum(alias.declaration)];
            if (!std.mem.eql(u8, self.graph.text(declaration.name), qualifier)) continue;
            if (found) |previous| {
                if (previous != alias.target) return error.AmbiguousModuleReference;
            } else found = alias.target;
        }
        if (found) |target| return target;
        // Transitional/compiler-generated qualifiers may still spell a module
        // directly; source import aliases never take this fallback.
        return self.findModuleBySpelling(qualifier);
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

fn pathEndsWith(path: []const u8, suffix: []const u8) bool {
    if (std.mem.eql(u8, path, suffix)) return true;
    if (!std.mem.endsWith(u8, path, suffix) or path.len <= suffix.len) return false;
    const boundary = path[path.len - suffix.len - 1];
    return boundary == '/' or boundary == '\\';
}

test "call input matching distinguishes deferred arguments from mismatches" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const int_ty: global_sg.GlobalTypeId = @enumFromInt(0);
    const bool_ty: global_sg.GlobalTypeId = @enumFromInt(1);
    const input_ty: global_sg.GlobalTypeId = @enumFromInt(2);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .builtin = .Bool });
    const field_name = try graph.addString(allocator, "value");
    try graph.fields.append(allocator, .{ .name = field_name, .ty = int_ty, .source = .{ .file_index = 0, .offset = 0 } });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } });
    try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 1 }, .ty = null, .content = .{ .bool_literal = false } });
    try graph.value_fields.append(allocator, .{ .name = field_name, .value = @enumFromInt(0) });
    try graph.nodes.append(allocator, .{
        .source = .{ .file_index = 0, .offset = 2 },
        .ty = input_ty,
        .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 1 }, .ty = input_ty } },
    });

    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    const expected: global_sg.FieldRange = .{ .start = 0, .len = 1 };
    try std.testing.expectEqual(Resolver.CallInputMatch.deferred, resolver.matchCallInput(expected, @enumFromInt(1)));
    graph.nodes.items[0].ty = bool_ty;
    try std.testing.expectEqual(Resolver.CallInputMatch.no_match, resolver.matchCallInput(expected, @enumFromInt(1)));
    graph.nodes.items[0].ty = int_ty;
    const matched = resolver.matchCallInput(expected, @enumFromInt(1));
    try std.testing.expectEqual(@as(u32, 4), matched.score);
}
test "global core resolver is graph-only" {
    try std.testing.expect(@sizeOf(Resolver) <= 112);
}

test "qualified lookup follows linked module alias" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "/workspace/app") };
    defer module.deinit(allocator);

    const app_dir = try graph.addString(allocator, "/workspace/app");
    const target_dir = try graph.addString(allocator, "/tool/more/_test_support/basic");
    const alias_name = try graph.addString(allocator, "support");
    try graph.declarations.append(allocator, .{
        .kind = .import_alias,
        .name = alias_name,
        .source = .{ .file_index = 0, .offset = 10 },
    });
    try graph.modules.append(allocator, .{ .dir = app_dir, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 1 } });
    try graph.modules.append(allocator, .{ .dir = target_dir, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 1, .len = 0 } });
    try graph.module_aliases.append(allocator, .{
        .owner = @enumFromInt(0),
        .declaration = @enumFromInt(0),
        .target = @enumFromInt(1),
        .source = .{ .file_index = 0, .offset = 24 },
    });

    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{module}, .offsets = &.{} };
    try std.testing.expectEqual(@as(global_sg.GlobalModuleId, @enumFromInt(1)), try resolver.findModuleForQualifier(0, "support"));
}

test "global declaration lookup preserves module visibility" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "app") };
    defer module.deinit(allocator);
    try module.strings.appendSlice(allocator, "helper_hidden");
    const helper = try graph.addString(allocator, "helper");
    const hidden = try graph.addString(allocator, "_hidden");
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.declarations.append(allocator, .{ .kind = .function, .name = helper, .source = source });
    try graph.declarations.append(allocator, .{ .kind = .function, .name = hidden, .source = source });
    try graph.modules.append(allocator, .{ .dir = try graph.addString(allocator, "app"), .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 0 } });
    try graph.modules.append(allocator, .{ .dir = try graph.addString(allocator, "dependency"), .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 2 } });
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{module}, .offsets = &.{} };
    const reference: module_entities.ExternalRef = .{ .kind = .function, .module_path = null, .name = .{ .start = 0, .len = 6 }, .source = source };
    try std.testing.expectError(error.UnknownGlobalDeclaration, resolver.resolveDeclaration(0, reference, &.{.function}));
    graph.modules.items[1].is_bundled_core = true;
    try std.testing.expectEqual(@as(global_sg.GlobalDeclId, @enumFromInt(0)), try resolver.resolveDeclaration(0, reference, &.{.function}));
    var private_reference = reference;
    private_reference.name = .{ .start = 6, .len = 7 };
    try std.testing.expectError(error.UnknownGlobalDeclaration, resolver.resolveDeclaration(0, private_reference, &.{.function}));
}
