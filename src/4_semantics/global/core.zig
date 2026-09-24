const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const module_views = @import("../module/views.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const reach_context = @import("reach_context.zig");
const module_linker = @import("module_linker.zig");
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
    pointer_type_calls: u64 = 0,
    pointer_type_candidates: u64 = 0,
    pointer_type_ns: u64 = 0,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    profile_io: ?std.Io = null,
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
                if (reference.module_path == null and reference.generic_arguments == null) {
                    const name = module.text(reference.name);
                    var resolved_builtin: ?primitives.BuiltinType = null;
                    inline for (@typeInfo(primitives.BuiltinType).@"enum".fields) |field| {
                        if (std.mem.eql(u8, name, field.name)) {
                            resolved_builtin = @enumFromInt(field.value);
                            break;
                        }
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
                if (self.graph.isTypeUnresolved(child)) continue;
                const mutability = if (node.ty) |old| switch (self.graph.types.items[@intFromEnum(old)]) {
                    .pointer => |pointer| blk: {
                        // The existing pointer already has the required semantic
                        // type when its child matches. Avoid interning it again,
                        // which otherwise scans every global type each round.
                        if (types.equal(self.graph, pointer.child, child)) continue;
                        break :blk pointer.mutability;
                    },
                    else => continue,
                } else continue;
                const pointer_type = try self.pointerType(child, mutability);
                if (node.ty != null and (node.ty.? == pointer_type or types.equal(self.graph, node.ty.?, pointer_type))) continue;
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
            .binding_declaration, .binding_use => |binding_id| {
                if (self.graph.isBindingTypeUnresolved(binding_id)) continue;
                const inferred = self.graph.bindings.items[@intFromEnum(binding_id)].ty;
                // An unresolved type is unequal even to itself in semantic
                // matching, but writing the same slot cannot advance the
                // fixed point.
                if (node.ty != null and (node.ty.? == inferred or types.equal(self.graph, node.ty.?, inferred))) continue;
                node.ty = inferred;
                changed = true;
            },
            .move_value => |value| {
                const inferred = self.graph.nodes.items[@intFromEnum(value)].ty orelse continue;
                if (node.ty != null and (node.ty.? == inferred or types.equal(self.graph, node.ty.?, inferred))) continue;
                node.ty = inferred;
                changed = true;
            },
            .binary_operation => |operation| {
                var left_ty = self.graph.nodes.items[@intFromEnum(operation.left)].ty orelse continue;
                var right_ty = self.graph.nodes.items[@intFromEnum(operation.right)].ty orelse continue;
                self.coerceIntegerPair(operation.left, &left_ty, operation.right, &right_ty);
                if (!self.isBuiltinArithmetic(left_ty, right_ty)) continue;
                if (node.ty != null and (node.ty.? == left_ty or types.equal(self.graph, node.ty.?, left_ty))) continue;
                node.ty = left_ty;
                changed = true;
            },
            else => {},
        };
        return changed;
    }

    pub fn defaultStringLiteralType(self: *const Resolver) ?global_sg.GlobalTypeId {
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.kind != .type or !std.mem.eql(u8, self.graph.text(declaration.name), "StringView")) continue;
            const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
            const owner = self.graph.moduleForDeclaration(id) orelse continue;
            if (!self.graph.modules.items[@intFromEnum(owner)].is_bundled_core) continue;
            const ty = declaration.type_id orelse continue;
            if (self.graph.isTypeUnresolved(ty)) continue;
            return ty;
        }
        return null;
    }

    pub fn materializeStringLiteralTypes(self: *Resolver) bool {
        const default_ty = self.defaultStringLiteralType() orelse return false;
        var changed = false;
        for (self.graph.nodes.items) |*node| {
            if (node.ty != null or node.content != .string_literal) continue;
            node.ty = default_ty;
            changed = true;
        }
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
        for (try self.graph.declarationsNamed(self.allocator, name)) |id| {
            const decl = self.graph.declarations.items[@intFromEnum(id)];
            if (!self.declarationVisible(current_module, id, module_filter)) continue;
            var allowed = false;
            for (kinds) |kind| if (decl.kind == kind) {
                allowed = true;
                break;
            };
            if (!allowed) continue;
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
        ambiguous,
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
        return self.matchFunctionNamed(current_module, self.modules[current_module].text(reference.name), module_filter, input_node);
    }

    /// Resolve a compiler-synthesized, unqualified call using the same ordinary
    /// overload rules as a source call. Semantic sugar must not manufacture a
    /// module-local ExternalRef merely to enter dispatch.
    pub fn matchUnqualifiedFunctionByName(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        input_node: global_sg.GlobalNodeId,
    ) !FunctionMatch {
        return self.matchFunctionNamed(current_module, name, null, input_node);
    }

    pub fn matchFunctionByNameWithReach(
        self: *Resolver,
        current_module: usize,
        reference: module_entities.ExternalRef,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !FunctionMatch {
        const module_filter = if (reference.module_path) |path|
            try self.findModuleForQualifier(current_module, self.modules[current_module].text(path))
        else
            null;
        return self.matchFunctionNamedWithReach(
            current_module,
            self.modules[current_module].text(reference.name),
            module_filter,
            input_node,
            context,
        );
    }

    pub fn matchUnqualifiedFunctionByNameWithReach(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !FunctionMatch {
        return self.matchFunctionNamedWithReach(current_module, name, null, input_node, context);
    }

    fn matchFunctionNamedWithReach(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !FunctionMatch {
        var best: ?global_sg.GlobalFunctionId = null;
        var best_score: u32 = 0;
        var tied = false;
        var saw_deferred = false;
        for (try self.graph.functionsNamed(self.allocator, name)) |id| {
            const function = self.graph.functions.items[@intFromEnum(id)];
            if (function.flags.is_abstract_dispatch) continue;
            if (!self.declarationVisible(current_module, function.declaration, module_filter)) continue;
            const score = switch (try self.matchCallInputWithReach(function.input, input_node, context)) {
                .no_match => continue,
                .deferred => {
                    saw_deferred = true;
                    continue;
                },
                .score => |score| score,
            };
            if (best == null or score > best_score) {
                best = id;
                best_score = score;
                tied = false;
            } else if (score == best_score) tied = true;
        }
        if (best) |function| {
            if (tied) return .ambiguous;
            return .{ .function = function };
        }
        if (saw_deferred) return .deferred;
        return .no_match;
    }

    fn matchFunctionNamed(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input_node: global_sg.GlobalNodeId,
    ) !FunctionMatch {
        var best: ?global_sg.GlobalFunctionId = null;
        var best_score: u32 = 0;
        var tied = false;
        var saw_deferred = false;
        for (try self.graph.functionsNamed(self.allocator, name)) |id| {
            const function = self.graph.functions.items[@intFromEnum(id)];
            if (function.flags.is_abstract_dispatch) continue;
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
                best = id;
                best_score = score;
                tied = false;
            } else if (score == best_score) tied = true;
        }
        if (best) |function| {
            if (tied) return .ambiguous;
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
            .ambiguous => error.AmbiguousGlobalFunction,
        };
    }

    pub fn resolveOperator(
        self: *Resolver,
        current_module: usize,
        operator: callable.OperatorKind,
        operand_nodes: []const global_sg.GlobalNodeId,
        operand_types: []const global_sg.GlobalTypeId,
    ) !global_sg.GlobalFunctionId {
        if (operand_nodes.len != operand_types.len) return error.InvalidCallInputArity;
        var best: ?global_sg.GlobalFunctionId = null;
        var best_score: u32 = 0;
        var tied = false;
        for (self.graph.functions.items, 0..) |function, raw| {
            if (raw >= self.graph.function_operators.items.len or self.graph.function_operators.items[raw] != operator) continue;
            if (function.input.len != operand_types.len) continue;
            if (!self.declarationVisible(current_module, function.declaration, null)) continue;
            var score: u32 = 0;
            var compatible = true;
            for (operand_types, 0..) |actual, index| {
                const expected = self.graph.fields.items[function.input.start + @as(u32, @intCast(index))].ty;
                if (types.equal(self.graph, expected, actual))
                    score += 4
                else if (self.callTypesCompatible(actual, expected) or self.contextualLiteralFits(operand_nodes[index], expected))
                    score += 3
                else if (types.isBuiltin(self.graph, expected, .Any))
                    score += 1
                else {
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
        const selected = self.graph.functions.items[@intFromEnum(best.?)];
        for (operand_nodes, 0..) |node, index| {
            const expected = self.graph.fields.items[selected.input.start + @as(u32, @intCast(index))].ty;
            _ = self.coerceContextualValue(node, expected);
        }
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
            const source_field = self.graph.fields.items[function.input.start + @as(u32, @intCast(index))];
            _ = self.coerceContextualValue(node, source_field.ty);
            try self.graph.value_fields.append(self.allocator, .{ .name = source_field.name, .value = node });
        }
        const ty = try self.structType(function.input);
        const source = if (nodes.len != 0) self.graph.nodes.items[@intFromEnum(nodes[0])].source else self.syntheticSource();
        return self.appendNode(source, ty, .{ .struct_value_literal = .{
            .fields = .{ .start = start, .len = @intCast(nodes.len) },
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
        if (reference.module_path == null and std.mem.eql(u8, module.text(reference.name), "length")) {
            const literal = switch (self.graph.node(input).content) {
                .struct_value_literal => |item| item,
                else => return .not_applicable,
            };
            if (literal.fields.len == 1) {
                const field = self.graph.value_fields.items[literal.fields.start];
                if (std.mem.eql(u8, self.graph.text(field.name), "value") or literal.dispatch_prefix_positional_count == 1) {
                    const measured = self.graph.node(field.value);
                    const length: ?u64 = switch (measured.content) {
                        .list_literal => |list| list.elements.len,
                        .array_literal => |array| array.length,
                        else => if (measured.ty) |ty| types.arrayLength(self.graph, ty) else null,
                    };
                    if (length) |count| {
                        const result = std.math.cast(i64, count) orelse return .deferred;
                        self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = .{
                            .source = self.sourceFor(reference.source, o),
                            .ty = try self.builtin(.UIntNative),
                            .content = .{ .int_literal = result },
                        };
                        self.stats.calls += 1;
                        return .resolved;
                    }
                    if (measured.ty == null or self.graph.isTypeUnresolved(measured.ty.?)) return .deferred;
                }
            }
        }
        if (reference.module_path == null and std.mem.eql(u8, module.text(reference.name), "size_of")) {
            const node = (try self.makeSizeOf(input, self.sourceFor(reference.source, o))) orelse return .deferred;
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
            self.stats.calls += 1;
            return .resolved;
        }
        if (reference.module_path == null and std.mem.eql(u8, module.text(reference.name), "alignment_of")) {
            const node = (try self.makeAlignmentOf(input, self.sourceFor(reference.source, o))) orelse return .deferred;
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
            self.stats.calls += 1;
            return .resolved;
        }
        if (reference.module_path == null and std.mem.eql(u8, module.text(reference.name), "type_of")) {
            const node = (try self.makeTypeOf(input, self.sourceFor(reference.source, o))) orelse return .deferred;
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
                } },
            };
            self.stats.calls += 1;
            return .resolved;
        }
        const reach = reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function);
        const function = switch (try self.matchFunctionByNameWithReach(module_index, reference, input, reach)) {
            .no_match => return .not_applicable,
            .deferred => return .deferred,
            .ambiguous => return .invalid,
            .function => |function| function,
        };
        if (!try self.completeCallInputWithReach(function, input, reach)) return .deferred;
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
        const measured = self.typeArgument(input) orelse return null;
        const size = types.sizeOf(self.graph, measured) catch return null;
        return try self.typeInfoLiteral(source, size);
    }

    fn makeAlignmentOf(self: *Resolver, input: global_sg.GlobalNodeId, source: primitives.SourceRef) !?global_sg.Node {
        const measured = self.typeArgument(input) orelse return null;
        const alignment = types.alignmentOf(self.graph, measured) catch return null;
        return try self.typeInfoLiteral(source, alignment);
    }

    fn makeTypeOf(self: *Resolver, input: global_sg.GlobalNodeId, source: primitives.SourceRef) !?global_sg.Node {
        const literal = switch (self.graph.node(input).content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            if (!std.mem.eql(u8, self.graph.text(field.name), "value")) continue;
            const value_ty = self.graph.node(field.value).ty orelse return null;
            return .{ .source = source, .ty = try self.builtin(.Type), .content = .{ .type_literal = value_ty } };
        }
        return null;
    }

    fn typeArgument(self: *const Resolver, input: global_sg.GlobalNodeId) ?global_sg.GlobalTypeId {
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
        return measured;
    }

    fn typeInfoLiteral(self: *Resolver, source: primitives.SourceRef, value: u64) !global_sg.Node {
        return .{
            .source = source,
            .ty = try self.builtin(.UIntNative),
            .content = .{ .int_literal = std.math.cast(i64, value) orelse return error.TypeSizeOverflow },
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
        if (self.graph.types.items[@intFromEnum(source_ty)] == .virtual) {
            const field_index: u32 = if (std.mem.eql(u8, field_name, "data") or std.mem.eql(u8, field_name, "data_ptr"))
                0
            else if (std.mem.eql(u8, field_name, "vtable"))
                1
            else
                return false;
            const any = try self.builtin(.Any);
            const pointer = try self.pointerType(any, .read_only);
            self.graph.nodes.items[@intFromEnum(target)] = .{
                .source = self.graph.nodes.items[@intFromEnum(source)].source,
                .ty = pointer,
                .content = .{ .struct_field_access = .{
                    .value = source,
                    .field_name = try self.graph.addString(self.allocator, field_name),
                    .field_index = field_index,
                } },
            };
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
        if (value.collapse_existing_pointer) switch (self.graph.types.items[@intFromEnum(child)]) {
            .pointer => |pointer| if (value.mutability == .read_only or pointer.mutability == .read_write) {
                self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = self.graph.node(child_node);
                return .resolved;
            },
            else => {},
        };
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
        const function = self.resolveOperator(module_index, .add, &.{ left, right }, &.{ left_ty, right_ty }) catch return false;
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

        // In equality tests a bare `..variant` denotes the choice tag, not a
        // value construction. Materialize that tag directly so payload-bearing
        // variants can participate in refinement without weakening normal
        // construction rules.
        if (value.operator == .equal or value.operator == .not_equal) {
            if (self.graph.nodes.items[@intFromEnum(left)].ty) |left_ty| {
                if (try self.materializeChoiceTagOperand(module_index, o, right, left_ty))
                    return self.patchChoiceTagComparison(o, value, left, right);
            }
            if (self.graph.nodes.items[@intFromEnum(right)].ty) |right_ty| {
                if (try self.materializeChoiceTagOperand(module_index, o, left, right_ty))
                    // Canonicalize choice-vs-tag comparisons for Safety and
                    // codegen regardless of source operand order.
                    return self.patchChoiceTagComparison(o, value, right, left);
            }
        }

        var left_ty = self.graph.nodes.items[@intFromEnum(left)].ty orelse return false;
        if (self.graph.nodes.items[@intFromEnum(right)].ty == null and
            self.contextualizeChoiceOperand(module_index, o, right, left_ty)) return false;
        var right_ty = self.graph.nodes.items[@intFromEnum(right)].ty orelse return false;
        self.coerceIntegerPair(left, &left_ty, right, &right_ty);
        const bool_ty = try self.builtin(.Bool);
        const target = globalizer.globalNode(o, value.node);
        const directly_comparable = self.isBuiltinComparable(left_ty, right_ty) or
            ((value.operator == .equal or value.operator == .not_equal) and self.isCEnumPair(left_ty, right_ty));
        if (directly_comparable) {
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
        const function = self.resolveOperator(module_index, operator, &.{ left, right }, &.{ left_ty, right_ty }) catch return false;
        const input = try self.makeCallInput(function, &.{ left, right });
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(left)].source,
            .ty = bool_ty,
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        self.stats.operators += 1;
        return true;
    }

    fn patchChoiceTagComparison(
        self: *Resolver,
        o: globalizer.Offsets,
        value: anytype,
        choice: global_sg.GlobalNodeId,
        tag: global_sg.GlobalNodeId,
    ) !bool {
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(choice)].source,
            .ty = try self.builtin(.Bool),
            .content = .{ .comparison = .{
                .operator = value.operator,
                .left = choice,
                .right = tag,
            } },
        };
        self.stats.operators += 1;
        return true;
    }

    fn materializeChoiceTagOperand(
        self: *Resolver,
        module_index: usize,
        o: globalizer.Offsets,
        node_id: global_sg.GlobalNodeId,
        choice_ty: global_sg.GlobalTypeId,
    ) !bool {
        if (types.variants(self.graph, choice_ty) == null) return false;
        const module = &self.modules[module_index];
        for (module.semantic.pending_operations.items) |pending| switch (pending) {
            .resolve_choice_literal => |choice| {
                if (globalizer.globalNode(o, choice.node) != node_id) continue;
                if (choice.payload != null) return false;
                const reference = module.semantic.external_refs.items[@intFromEnum(choice.option)];
                const hit = types.findVariant(self.graph, choice_ty, module.text(reference.name)) orelse return false;
                self.graph.nodes.items[@intFromEnum(node_id)] = .{
                    .source = .{
                        .file_index = o.file_base + reference.source.file_index,
                        .offset = reference.source.offset,
                    },
                    .ty = try self.builtin(.Int32),
                    .content = .{ .int_literal = hit.variant.value },
                };
                return true;
            },
            else => {},
        };
        return false;
    }

    fn contextualizeChoiceOperand(self: *Resolver, module_index: usize, o: globalizer.Offsets, node_id: global_sg.GlobalNodeId, expected: global_sg.GlobalTypeId) bool {
        const module = &self.modules[module_index];
        for (module.semantic.pending_operations.items) |pending| switch (pending) {
            .resolve_choice_literal => |choice| {
                if (globalizer.globalNode(o, choice.node) != node_id) continue;
                if (choice.expected_type != null) return false;
                if (types.variants(self.graph, expected) == null) return false;
                self.graph.nodes.items[@intFromEnum(node_id)].ty = expected;
                return true;
            },
            else => {},
        };
        return false;
    }

    fn resolveIndex(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const collection = globalizer.globalNode(o, value.value);
        const index = globalizer.globalNode(o, value.index);

        // A list literal is a compile-time tuple-like value until context
        // materializes it as an array. Direct literal indexing therefore
        // selects the element without requiring an array type first.
        if (value.store_value == null) switch (self.graph.node(collection).content) {
            .list_literal => |literal| switch (self.graph.node(index).content) {
                .int_literal => |raw_index| if (raw_index >= 0 and raw_index < @as(i64, @intCast(literal.elements.len))) {
                    const selected = self.graph.node_refs.items[
                        literal.elements.start + @as(u32, @intCast(raw_index))
                    ];
                    self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] =
                        self.graph.node(selected);
                    self.stats.indexes += 1;
                    return .resolved;
                },
                else => {},
            },
            else => {},
        };

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
        const operator: callable.OperatorKind = value.operator;
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
        const function = self.resolveOperator(module_index, operator, operands[0..count], operand_types[0..count]) catch blk: {
            break :blk self.resolveAddressedIndexOperator(
                module_index,
                operator,
                collection_ty,
                operands[0..count],
                operand_types[0..count],
            ) orelse return .not_applicable;
        };
        const receiver_ty = self.graph.fields.items[self.graph.functions.items[@intFromEnum(function)].input.start].ty;
        if (!types.equal(self.graph, collection_ty, receiver_ty) and !self.callTypesCompatible(collection_ty, receiver_ty)) {
            const address: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
            try self.graph.nodes.append(self.allocator, .{
                .source = self.graph.node(collection).source,
                .ty = receiver_ty,
                .content = .{ .address_of = collection },
            });
            operands[0] = address;
        }
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

    fn resolveAddressedIndexOperator(self: *Resolver, module_index: usize, operator: callable.OperatorKind, collection_ty: global_sg.GlobalTypeId, operand_nodes: []const global_sg.GlobalNodeId, operand_types: []const global_sg.GlobalTypeId) ?global_sg.GlobalFunctionId {
        var chosen: ?global_sg.GlobalFunctionId = null;
        for (self.graph.functions.items, 0..) |candidate, raw| {
            if (raw >= self.graph.function_operators.items.len or self.graph.function_operators.items[raw] != operator) continue;
            if (candidate.input.len != operand_types.len) continue;
            if (!self.declarationVisible(module_index, candidate.declaration, null)) continue;
            const receiver = self.graph.fields.items[candidate.input.start].ty;
            const pointer = switch (self.graph.resolvedSemanticType(receiver) orelse continue) {
                .pointer => |value| value,
                else => continue,
            };
            if (!types.equal(self.graph, collection_ty, receiver) and
                !self.callTypesCompatible(collection_ty, receiver) and
                !types.equal(self.graph, pointer.child, collection_ty)) continue;
            var matches = true;
            for (1..operand_types.len) |offset| {
                const expected = self.graph.fields.items[candidate.input.start + @as(u32, @intCast(offset))].ty;
                if (!types.equal(self.graph, expected, operand_types[offset]) and
                    !self.callTypesCompatible(operand_types[offset], expected) and
                    !self.contextualLiteralFits(operand_nodes[offset], expected))
                {
                    matches = false;
                    break;
                }
            }
            if (!matches) continue;
            if (chosen != null) return null;
            chosen = @enumFromInt(@as(u32, @intCast(raw)));
        }
        return chosen;
    }

    pub const CallInputMatch = union(enum) {
        no_match,
        deferred,
        score: u32,
    };

    /// Optional language-level compatibility layered above Core. Reach lookup
    /// owns lexical traversal and value adaptation; higher semantic layers may
    /// contribute relations such as concrete-to-abstract compatibility without
    /// introducing an Abstract dependency into Core.
    pub const AdditionalTypeCompatibility = struct {
        context: *const anyopaque,
        compatible: *const fn (*const anyopaque, global_sg.GlobalTypeId, global_sg.GlobalTypeId) bool,
    };

    pub const ReachedDefaultProbe = enum { unavailable, deferred, available };
    const ReachedAdaptation = enum { direct, address };

    pub fn matchCallInput(self: *Resolver, expected_fields: global_sg.FieldRange, input_node: global_sg.GlobalNodeId) CallInputMatch {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input_node)].content) {
            .struct_value_literal => |value| value,
            else => return .no_match,
        };
        if (!self.callInputNamesMatch(expected_fields, literal)) return .no_match;
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
                } else if (self.contextualLiteralFits(node, expected.ty)) {
                    score += 3;
                } else switch (supplied_node.content) {
                    .string_literal, .struct_value_literal => return .no_match,
                    else => return .deferred,
                }
            } else if (expected.default_value == null) return .no_match;
        }
        return .{ .score = score };
    }

    pub fn matchCallInputWithReach(
        self: *Resolver,
        expected_fields: global_sg.FieldRange,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !CallInputMatch {
        return self.matchCallInputWithReachCompatibility(
            expected_fields,
            input_node,
            context,
            null,
        );
    }

    pub fn matchCallInputWithReachCompatibility(
        self: *Resolver,
        expected_fields: global_sg.FieldRange,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
        additional: ?AdditionalTypeCompatibility,
    ) !CallInputMatch {
        const base = self.matchCallInput(expected_fields, input_node);
        if (base != .score) return base;
        const literal = switch (self.graph.nodes.items[@intFromEnum(input_node)].content) {
            .struct_value_literal => |value| value,
            else => return .no_match,
        };
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            if (self.callArgument(literal, offset, expected.name) != null) continue;
            const fallback = expected.default_value orelse return .no_match;
            if (self.graph.nodes.items[@intFromEnum(fallback)].content != .reach_directive) continue;
            switch (try self.probeReachedDefaultWithCompatibility(
                context,
                expected,
                fallback,
                additional,
            )) {
                .available => {},
                .deferred => return .deferred,
                .unavailable => return .no_match,
            }
        }
        return base;
    }

    pub const ReachedField = struct {
        hit: types.FieldHit,
        dereference_child: ?global_sg.GlobalTypeId = null,
    };

    /// A reach path follows capability fields through references without
    /// requiring explicit dereference syntax at each segment.
    pub fn reachedField(
        self: *const Resolver,
        current_ty: global_sg.GlobalTypeId,
        name: []const u8,
    ) ?ReachedField {
        const base_ty, const dereference_child = switch (self.graph.types.items[@intFromEnum(current_ty)]) {
            .pointer => |pointer| .{ pointer.child, pointer.child },
            else => .{ current_ty, null },
        };
        const hit = types.findField(self.graph, base_ty, name) orelse return null;
        return .{ .hit = hit, .dereference_child = dereference_child };
    }

    pub fn probeReachedDefaultWithCompatibility(
        self: *Resolver,
        context: reach_context.Context,
        expected_field: global_sg.Field,
        default_node: global_sg.GlobalNodeId,
        additional: ?AdditionalTypeCompatibility,
    ) !ReachedDefaultProbe {
        const reach_id = self.graph.nodes.items[@intFromEnum(default_node)].content.reach_directive;
        const reach = self.graph.reaches.items[@intFromEnum(reach_id)];
        var saw_deferred = false;

        for (self.graph.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len]) |alternative| {
            if (alternative.segments.len == 0) continue;
            const segments = self.graph.reach_segments.items[alternative.segments.start..][0..alternative.segments.len];
            const root_name = self.graph.text(segments[0]);
            var scope_index = context.bindingCount();
            while (scope_index > 0) {
                scope_index -= 1;
                const binding_id = context.bindingAt(scope_index);
                const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                if (!std.mem.eql(u8, self.graph.text(binding.name), root_name)) continue;
                if (self.graph.isBindingTypeUnresolved(binding_id) or self.graph.isTypeUnresolved(binding.ty)) {
                    saw_deferred = true;
                    continue;
                }

                var current_ty = binding.ty;
                var valid = true;
                for (segments[1..]) |segment| {
                    if (self.graph.isTypeUnresolved(current_ty)) {
                        saw_deferred = true;
                        valid = false;
                        break;
                    }
                    const step = self.reachedField(current_ty, self.graph.text(segment)) orelse {
                        valid = false;
                        break;
                    };
                    current_ty = step.hit.field.storage_type orelse step.hit.field.ty;
                }
                if (!valid) continue;
                if (self.graph.isTypeUnresolved(current_ty)) {
                    saw_deferred = true;
                    continue;
                }
                if (self.reachedAdaptation(current_ty, expected_field.ty, additional) != null)
                    return .available;
            }
        }

        const owner_id = context.ownerFunction() orelse
            return if (saw_deferred) .deferred else .unavailable;
        const owner = self.graph.functions.items[@intFromEnum(owner_id)];
        const owner_name = self.graph.text(self.graph.declarations.items[@intFromEnum(owner.declaration)].name);
        if (std.mem.eql(u8, owner_name, "main"))
            return if (saw_deferred) .deferred else .unavailable;

        for (self.graph.fields.items[owner.input.start..][0..owner.input.len]) |field| {
            if (!std.mem.eql(u8, self.graph.text(field.name), self.graph.text(expected_field.name))) continue;
            if (self.graph.isTypeUnresolved(field.ty) or self.graph.isTypeUnresolved(expected_field.ty))
                return .deferred;
            return if (self.typesCompatibleWithAdditional(field.ty, expected_field.ty, additional) or
                self.typesCompatibleWithAdditional(expected_field.ty, field.ty, additional))
                .available
            else
                .unavailable;
        }

        // Completion may propagate a missing reach parameter into a non-main
        // caller. Ranking can acknowledge that possibility without mutating
        // the caller while probing overloads.
        return .available;
    }

    fn typesCompatibleWithAdditional(
        self: *const Resolver,
        actual: global_sg.GlobalTypeId,
        expected: global_sg.GlobalTypeId,
        additional: ?AdditionalTypeCompatibility,
    ) bool {
        if (types.equal(self.graph, actual, expected) or self.callTypesCompatible(actual, expected))
            return true;
        if (additional) |policy|
            return policy.compatible(policy.context, actual, expected);
        return false;
    }

    fn reachedAdaptation(
        self: *const Resolver,
        actual: global_sg.GlobalTypeId,
        expected: global_sg.GlobalTypeId,
        additional: ?AdditionalTypeCompatibility,
    ) ?ReachedAdaptation {
        if (self.typesCompatibleWithAdditional(actual, expected, additional))
            return .direct;

        const expected_pointer = switch (self.graph.types.items[@intFromEnum(expected)]) {
            .pointer => |pointer| pointer,
            else => return null,
        };
        if (self.typesCompatibleWithAdditional(actual, expected_pointer.child, additional))
            return .address;
        return null;
    }

    pub fn callInputNamesMatch(self: *const Resolver, expected_fields: global_sg.FieldRange, literal: anytype) bool {
        if (literal.fields.len > expected_fields.len) return false;
        for (0..literal.fields.len) |supplied_offset| {
            const supplied = self.graph.value_fields.items[literal.fields.start + @as(u32, @intCast(supplied_offset))];
            const name = self.graph.text(supplied.name);
            if (supplied_offset < literal.dispatch_prefix_positional_count or name.len == 0) continue;
            var known = false;
            for (self.graph.fields.items[expected_fields.start..][0..expected_fields.len]) |expected| {
                if (std.mem.eql(u8, name, self.graph.text(expected.name))) {
                    known = true;
                    break;
                }
            }
            if (!known) return false;
        }
        return true;
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
        // `Any` is the wildcard value type. A reference to a concrete value is
        // compatible with `&Any`/`$&Any`, subject to the mutability rule above.
        // Do not recurse through pointer constructors here: that would make
        // mutable pointer slots covariant (`&&Int32` -> `&&Any`).
        if (types.isBuiltin(self.graph, expected_pointer.child, .Any)) return true;
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

    fn completeCallInputWithReach(
        self: *Resolver,
        function_id: global_sg.GlobalFunctionId,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !bool {
        return self.completeCallInputFieldsWithReach(
            self.graph.functions.items[@intFromEnum(function_id)].input,
            input_node,
            context,
        );
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
        };
        return true;
    }

    pub fn completeCallInputFieldsWithReach(
        self: *Resolver,
        expected_fields: global_sg.FieldRange,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !bool {
        return self.completeCallInputFieldsWithReachCompatibility(
            expected_fields,
            input_node,
            context,
            null,
        );
    }

    pub fn completeCallInputFieldsWithReachCompatibility(
        self: *Resolver,
        expected_fields: global_sg.FieldRange,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
        additional: ?AdditionalTypeCompatibility,
    ) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input_node)].content) {
            .struct_value_literal => |value| value,
            else => return false,
        };
        const node_mark = self.graph.nodes.items.len;
        const field_mark = self.graph.value_fields.items.len;
        var published = false;
        defer if (!published) {
            self.graph.nodes.shrinkRetainingCapacity(node_mark);
            self.graph.value_fields.shrinkRetainingCapacity(field_mark);
        };
        const start: u32 = @intCast(field_mark);
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            var node = self.callArgument(literal, offset, expected.name);
            if (node == null) {
                const fallback = expected.default_value orelse return false;
                node = if (self.graph.nodes.items[@intFromEnum(fallback)].content == .reach_directive)
                    try self.resolveReachedDefaultWithCompatibility(
                        context,
                        fallback,
                        expected.ty,
                        additional,
                    )
                else
                    fallback;
                if (node == null and self.graph.nodes.items[@intFromEnum(fallback)].content == .reach_directive)
                    node = try self.propagateReachedDefaultWithCompatibility(
                        context.ownerFunction(),
                        expected,
                        fallback,
                        additional,
                    );
            }
            const value = node orelse return false;
            _ = self.coerceContextualLiteral(value, expected.ty);
            try self.graph.value_fields.append(self.allocator, .{ .name = expected.name, .value = value });
        }
        const ty = try self.structType(expected_fields);
        self.graph.nodes.items[@intFromEnum(input_node)].ty = ty;
        self.graph.nodes.items[@intFromEnum(input_node)].content.struct_value_literal = .{
            .fields = .{ .start = start, .len = expected_fields.len },
        };
        published = true;
        return true;
    }

    /// A local `#reach` declaration uses the same lexical alternatives and
    /// concrete-to-abstract adaptation as an omitted reached call argument.
    /// Its declared binding type remains the visible interface; the returned
    /// expression retains the selected value's concrete type.
    pub fn resolveReachedBindingWithCompatibility(
        self: *Resolver,
        context: reach_context.Context,
        reach_node: global_sg.GlobalNodeId,
        binding: global_sg.GlobalBindingId,
        additional: ?AdditionalTypeCompatibility,
    ) !?global_sg.GlobalNodeId {
        const declared = self.graph.bindings.items[@intFromEnum(binding)];
        if (try self.resolveReachedDefaultWithCompatibility(context, reach_node, declared.ty, additional)) |node|
            return node;
        return self.propagateReachedDefaultWithCompatibility(context.ownerFunction(), .{
            .name = declared.name,
            .ty = declared.ty,
            .source = declared.source,
            .default_value = reach_node,
        }, reach_node, additional);
    }

    fn resolveReachedDefaultWithCompatibility(
        self: *Resolver,
        context: reach_context.Context,
        default_node: global_sg.GlobalNodeId,
        expected: global_sg.GlobalTypeId,
        additional: ?AdditionalTypeCompatibility,
    ) !?global_sg.GlobalNodeId {
        const reach_id = self.graph.nodes.items[@intFromEnum(default_node)].content.reach_directive;
        const reach = self.graph.reaches.items[@intFromEnum(reach_id)];
        const source = self.graph.nodes.items[@intFromEnum(default_node)].source;
        for (self.graph.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len]) |alternative| {
            if (alternative.segments.len == 0) continue;
            const segments = self.graph.reach_segments.items[alternative.segments.start..][0..alternative.segments.len];
            const root_name = self.graph.text(segments[0]);
            var scope_index = context.bindingCount();
            while (scope_index > 0) {
                scope_index -= 1;
                const binding_id = context.bindingAt(scope_index);
                const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                if (!std.mem.eql(u8, self.graph.text(binding.name), root_name)) continue;
                if (self.graph.isBindingTypeUnresolved(binding_id) or self.graph.isTypeUnresolved(binding.ty)) continue;
                var current_ty = binding.ty;
                var hits: std.ArrayList(ReachedField) = .empty;
                defer hits.deinit(self.allocator);
                var valid = true;
                for (segments[1..]) |segment| {
                    if (self.graph.isTypeUnresolved(current_ty)) {
                        valid = false;
                        break;
                    }
                    const step = self.reachedField(current_ty, self.graph.text(segment)) orelse {
                        valid = false;
                        break;
                    };
                    try hits.append(self.allocator, step);
                    current_ty = step.hit.field.storage_type orelse step.hit.field.ty;
                }
                if (self.graph.isTypeUnresolved(current_ty)) valid = false;
                if (!valid) continue;
                const adaptation = self.reachedAdaptation(current_ty, expected, additional) orelse continue;

                var node: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
                try self.graph.nodes.append(self.allocator, .{
                    .source = source,
                    .ty = binding.ty,
                    .content = .{ .binding_use = binding_id },
                });
                for (hits.items) |step| {
                    if (step.dereference_child) |child| {
                        const pointer_type = self.graph.nodes.items[@intFromEnum(node)].ty orelse return null;
                        const dereferenced: global_sg.GlobalNodeId = @enumFromInt(
                            @as(u32, @intCast(self.graph.nodes.items.len)),
                        );
                        try self.graph.nodes.append(self.allocator, .{
                            .source = source,
                            .ty = child,
                            .content = .{ .dereference = .{
                                .pointer = node,
                                .ty = child,
                                .pointer_type = pointer_type,
                            } },
                        });
                        node = dereferenced;
                    }

                    const hit = step.hit;
                    const next: global_sg.GlobalNodeId = @enumFromInt(
                        @as(u32, @intCast(self.graph.nodes.items.len)),
                    );
                    try self.graph.nodes.append(self.allocator, .{
                        .source = source,
                        .ty = hit.field.storage_type orelse hit.field.ty,
                        .content = .{ .struct_field_access = .{
                            .value = node,
                            .field_name = hit.field.name,
                            .field_index = hit.index,
                        } },
                    });
                    node = next;
                }

                if (adaptation == .address) {
                    const expected_pointer = self.graph.types.items[@intFromEnum(expected)].pointer;
                    const pointer_ty = try self.pointerType(current_ty, expected_pointer.mutability);
                    const addressed: global_sg.GlobalNodeId = @enumFromInt(
                        @as(u32, @intCast(self.graph.nodes.items.len)),
                    );
                    try self.graph.nodes.append(self.allocator, .{
                        .source = source,
                        .ty = pointer_ty,
                        .content = .{ .address_of = node },
                    });
                    node = addressed;
                }
                return node;
            }
        }
        return null;
    }

    fn propagateReachedDefaultWithCompatibility(
        self: *Resolver,
        owner_id: ?global_sg.GlobalFunctionId,
        reached_field: global_sg.Field,
        default_node: global_sg.GlobalNodeId,
        additional: ?AdditionalTypeCompatibility,
    ) !?global_sg.GlobalNodeId {
        const resolved_owner = owner_id orelse return null;
        const owner = &self.graph.functions.items[@intFromEnum(resolved_owner)];
        const owner_name = self.graph.text(self.graph.declarations.items[@intFromEnum(owner.declaration)].name);
        if (std.mem.eql(u8, owner_name, "main")) return null;

        for (0..owner.input.len) |offset| {
            const field = self.graph.fields.items[owner.input.start + @as(u32, @intCast(offset))];
            if (!std.mem.eql(u8, self.graph.text(field.name), self.graph.text(reached_field.name))) continue;
            if (!self.typesCompatibleWithAdditional(field.ty, reached_field.ty, additional) and
                !self.typesCompatibleWithAdditional(reached_field.ty, field.ty, additional)) return null;
            if (offset >= owner.input_bindings.len) return null;
            const binding = self.graph.binding_refs.items[owner.input_bindings.start + @as(u32, @intCast(offset))];
            const node: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
            try self.graph.nodes.append(self.allocator, .{
                .source = self.graph.nodes.items[@intFromEnum(default_node)].source,
                .ty = self.graph.bindings.items[@intFromEnum(binding)].ty,
                .content = .{ .binding_use = binding },
            });
            return node;
        }

        const old_input = owner.input;
        const old_bindings = owner.input_bindings;
        const copied_fields = try self.allocator.dupe(global_sg.Field, self.graph.fields.items[old_input.start..][0..old_input.len]);
        defer self.allocator.free(copied_fields);
        const copied_bindings = try self.allocator.dupe(global_sg.GlobalBindingId, self.graph.binding_refs.items[old_bindings.start..][0..old_bindings.len]);
        defer self.allocator.free(copied_bindings);
        const field_start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.appendSlice(self.allocator, copied_fields);
        try self.graph.fields.append(self.allocator, .{
            .name = reached_field.name,
            .ty = reached_field.ty,
            .storage_type = reached_field.storage_type,
            .source = reached_field.source,
            .default_value = default_node,
        });
        const binding_id: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.graph.bindings.items.len)));
        try self.graph.bindings.append(self.allocator, .{
            .name = reached_field.name,
            .source = reached_field.source,
            .ty = reached_field.ty,
            .mutability = .constant,
        });
        const binding_start: u32 = @intCast(self.graph.binding_refs.items.len);
        try self.graph.binding_refs.appendSlice(self.allocator, copied_bindings);
        try self.graph.binding_refs.append(self.allocator, binding_id);
        owner.input = .{ .start = field_start, .len = old_input.len + 1 };
        owner.input_bindings = .{ .start = binding_start, .len = old_bindings.len + 1 };

        const node: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{
            .source = self.graph.nodes.items[@intFromEnum(default_node)].source,
            .ty = reached_field.ty,
            .content = .{ .binding_use = binding_id },
        });
        return node;
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

    pub fn builtin(self: *Resolver, builtin_type: primitives.BuiltinType) !global_sg.GlobalTypeId {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .builtin => |value| if (value == builtin_type) return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .builtin = builtin_type });
        return id;
    }

    pub fn pointerType(self: *Resolver, child: global_sg.GlobalTypeId, mutability: primitives.PointerMutability) !global_sg.GlobalTypeId {
        const start = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        defer if (self.profile_io) |io| {
            self.stats.pointer_type_ns += @intCast(std.Io.Timestamp.now(io, .boot).nanoseconds - start);
        };
        if (self.profile_io != null) self.stats.pointer_type_calls += 1;
        for (self.graph.types.items, 0..) |ty, raw| {
            if (self.profile_io != null) self.stats.pointer_type_candidates += 1;
            switch (ty) {
                .pointer => |pointer| if (pointer.mutability == mutability and types.equal(self.graph, pointer.child, child))
                    return @enumFromInt(@as(u32, @intCast(raw))),
                else => {},
            }
        }
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
        // Default integer literals follow the typed operand, including typed
        // constants produced by compile-time operations such as size_of.
        if (types.isBuiltin(self.graph, right_ty.*, .Int32) and self.coerceIntegerLiteral(right, left_ty.*)) {
            right_ty.* = left_ty.*;
            return;
        }
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

    pub fn contextualLiteralFits(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        if (self.integerLiteralFits(node, target)) return true;
        switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .string_literal => return switch (self.graph.types.items[@intFromEnum(target)]) {
                .pointer => |pointer| pointer.mutability == .read_only and types.isBuiltin(self.graph, pointer.child, .Char),
                else => false,
            },
            .struct_value_literal => |literal| return self.contextualStructLiteralFits(literal, target),
            .list_literal => |literal| return self.contextualListLiteralFits(literal, target),
            else => return false,
        }
    }

    fn contextualListLiteralFits(self: *const Resolver, literal: anytype, target: global_sg.GlobalTypeId) bool {
        const element = types.arrayElement(self.graph, target) orelse return false;
        const length = types.arrayLength(self.graph, target) orelse return false;
        if (literal.elements.len != length) return false;
        for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |item| {
            const node = self.graph.node(item);
            if (node.ty) |actual| {
                if (types.equal(self.graph, actual, element) or self.callTypesCompatible(actual, element) or
                    self.contextualLiteralFits(item, element)) continue;
            } else if (self.contextualLiteralFits(item, element)) continue;
            return false;
        }
        return true;
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
        if (self.graph.node(node).content == .list_literal and self.contextualListLiteralFits(self.graph.node(node).content.list_literal, target)) {
            const literal = self.graph.node(node).content.list_literal;
            const element = types.arrayElement(self.graph, target) orelse return false;
            for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |item|
                _ = self.coerceContextualValue(item, element);
            self.graph.nodes.items[@intFromEnum(node)].content = .{ .array_literal = .{
                .elements = literal.elements,
                .element_type = element,
                .length = literal.elements.len,
            } };
            self.graph.nodes.items[@intFromEnum(node)].ty = target;
            return true;
        }
        if (self.graph.nodes.items[@intFromEnum(node)].content != .struct_value_literal and
            self.coerceContextualLiteral(node, target)) return true;
        const current = self.graph.nodes.items[@intFromEnum(node)].ty;
        const literal = switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .struct_value_literal => |value| value,
            else => {
                if (current == null) {
                    self.graph.nodes.items[@intFromEnum(node)].ty = target;
                    return true;
                }
                return false;
            },
        };
        // Void is represented by an empty aggregate value, but unlike normal
        // structural types it has no field range. Context must therefore
        // materialize the empty literal directly instead of asking for fields.
        if (types.isBuiltin(self.graph, target, .Void) and literal.fields.len == 0) {
            self.graph.nodes.items[@intFromEnum(node)].ty = target;
            return true;
        }
        const expected_fields = types.fields(self.graph, target) orelse return false;
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            const actual = self.callArgument(literal, offset, expected.name) orelse continue;
            _ = self.coerceContextualValue(actual, expected.ty);
        }
        self.graph.nodes.items[@intFromEnum(node)].ty = target;
        return true;
    }

    pub fn materializeAssignmentValues(self: *Resolver) bool {
        var changed = false;
        for (self.graph.bindings.items, 0..) |binding, raw| {
            if (self.graph.isBindingTypeUnresolved(@enumFromInt(@as(u32, @intCast(raw))))) continue;
            const initialization = binding.initialization orelse continue;
            const current = self.graph.node(initialization).ty;
            if (current == null or (!types.equal(self.graph, current.?, binding.ty) and self.contextualLiteralFits(initialization, binding.ty)))
                if (self.coerceContextualValue(initialization, binding.ty)) {
                    changed = true;
                };
        }
        for (self.graph.nodes.items) |node| {
            const assignment = switch (node.content) {
                .assignment => |value| value,
                .pointer_assignment => |value| {
                    const pointer_ty = self.graph.node(value.pointer).ty orelse continue;
                    const pointer = switch (self.graph.semanticType(pointer_ty)) {
                        .pointer => |item| item,
                        else => continue,
                    };
                    const current = self.graph.node(value.value).ty;
                    if (current == null or (!types.equal(self.graph, current.?, pointer.child) and self.contextualLiteralFits(value.value, pointer.child)))
                        if (self.coerceContextualValue(value.value, pointer.child)) {
                            changed = true;
                        };
                    continue;
                },
                else => continue,
            };
            if (self.graph.isBindingTypeUnresolved(assignment.binding)) continue;
            const current = self.graph.node(assignment.value).ty;
            const expected = self.graph.binding(assignment.binding).ty;
            if (current != null and (types.equal(self.graph, current.?, expected) or !self.contextualLiteralFits(assignment.value, expected))) continue;
            // Assignment destinations supply the contextual shape of anonymous
            // aggregates before summary inference and codegen consume them.
            if (self.coerceContextualValue(assignment.value, self.graph.binding(assignment.binding).ty)) changed = true;
        }
        return changed;
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

    fn isCEnumPair(self: *const Resolver, a: global_sg.GlobalTypeId, b: global_sg.GlobalTypeId) bool {
        if (!types.equal(self.graph, a, b)) return false;
        return switch (self.graph.resolvedSemanticType(a) orelse return false) {
            .declared => |decl| self.graph.declaration(decl).choice_layout == .c_enum,
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
        // Local lexical imports are lowered to their original path spelling.
        // Reuse the linker algorithm so every source import has one identity rule.
        return module_linker.resolveImportPath(self.allocator, self.graph, self.modules, current_module, qualifier);
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
        .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 1 } } },
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
test "assignment context materializes anonymous aggregate and child types" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    const name = try graph.addString(allocator, "value");
    const int_ty: global_sg.GlobalTypeId = @enumFromInt(0);
    const aggregate_ty: global_sg.GlobalTypeId = @enumFromInt(1);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.fields.append(allocator, .{ .name = name, .ty = int_ty, .source = source });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } });
    try graph.bindings.append(allocator, .{ .name = name, .source = source, .ty = aggregate_ty, .mutability = .variable });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .int_literal = 7 } });
    try graph.value_fields.append(allocator, .{ .name = name, .value = @enumFromInt(0) });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 1 } } } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = aggregate_ty, .content = .{ .assignment = .{ .binding = @enumFromInt(0), .value = @enumFromInt(1) } } });
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    try std.testing.expect(resolver.materializeAssignmentValues());
    try std.testing.expectEqual(aggregate_ty, graph.nodes.items[1].ty.?);
    try std.testing.expectEqual(int_ty, graph.nodes.items[0].ty.?);
    try std.testing.expect(!resolver.materializeAssignmentValues());
}

test "default integer operands preserve typed compile-time constants" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .UIntNative });
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.nodes.append(allocator, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 8 } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = @enumFromInt(1), .content = .{ .int_literal = 2 } });
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    var left: global_sg.GlobalTypeId = @enumFromInt(0);
    var right: global_sg.GlobalTypeId = @enumFromInt(1);
    resolver.coerceIntegerPair(@enumFromInt(0), &left, @enumFromInt(1), &right);
    try std.testing.expectEqual(@as(global_sg.GlobalTypeId, @enumFromInt(0)), left);
    try std.testing.expectEqual(left, right);
    graph.nodes.items[1].ty = @enumFromInt(1);
    right = @enumFromInt(1);
    resolver.coerceIntegerPair(@enumFromInt(1), &right, @enumFromInt(0), &left);
    try std.testing.expectEqual(left, right);
}

test "typed integer initializer adopts its binding context" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .builtin = .UIntNative });
    const name = try graph.addString(allocator, "count");
    try graph.nodes.append(allocator, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 131 } });
    try graph.bindings.append(allocator, .{ .name = name, .source = source, .ty = @enumFromInt(1), .initialization = @enumFromInt(0), .mutability = .constant });
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    try std.testing.expect(resolver.materializeAssignmentValues());
    try std.testing.expectEqual(@as(global_sg.GlobalTypeId, @enumFromInt(1)), graph.node(@enumFromInt(0)).ty.?);
    try std.testing.expect(!resolver.materializeAssignmentValues());
}

test "address type materializes after its child resolves" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    const unresolved_ty: global_sg.GlobalTypeId = @enumFromInt(0);
    const bool_ty: global_sg.GlobalTypeId = @enumFromInt(1);
    const bool_pointer_ty: global_sg.GlobalTypeId = @enumFromInt(2);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .builtin = .Bool });
    try graph.types.append(allocator, .{ .pointer = .{ .child = bool_ty, .mutability = .read_only } });
    try graph.markTypeUnresolved(allocator, unresolved_ty);
    try graph.nodes.append(allocator, .{ .source = source, .ty = unresolved_ty, .content = .{ .int_literal = 7 } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = bool_pointer_ty, .content = .{ .address_of = @enumFromInt(0) } });

    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    try std.testing.expect(!try resolver.materializeAddresses());

    graph.types.items[@intFromEnum(unresolved_ty)] = .{ .builtin = .Int32 };
    try std.testing.expect(graph.reconcileTypeResolution());
    try std.testing.expect(try resolver.materializeAddresses());
    const result_pointer = switch (graph.semanticType(graph.node(@enumFromInt(1)).ty.?)) {
        .pointer => |pointer| pointer,
        else => return error.ExpectedPointerType,
    };
    try std.testing.expectEqual(unresolved_ty, result_pointer.child);
    try std.testing.expectEqual(primitives.PointerMutability.read_only, result_pointer.mutability);
}

test "global core resolver is graph-only" {
    try std.testing.expect(!@hasField(Resolver, "abstract_context"));
    try std.testing.expect(!@hasField(Resolver, "abstract_compatible"));
    try std.testing.expect(@sizeOf(Resolver) <= 160);
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
