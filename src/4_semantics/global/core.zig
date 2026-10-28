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
const c_abi = @import("c_abi.zig");
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
    pub const CapturedExpressions = struct {
        context: *anyopaque,
        checkpoint: *const fn (*anyopaque) @import("generic_functions.zig").Resolver.SideEffectCheckpoint,
        rollback: *const fn (*anyopaque, @import("generic_functions.zig").Resolver.SideEffectCheckpoint) void,
        instantiate: *const fn (*anyopaque, u32, reach_context.Context) anyerror!global_sg.GlobalNodeId,
    };

    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    profile_io: ?std.Io = null,
    scan_profile: ?*@import("resolution_profile.zig").Profile = null,
    captured_expressions: ?*const CapturedExpressions = null,

    stats: Stats = .{},
    // Explicit interactive namespace; ordinary modules never acquire visibility
    // through this path merely because another module was loaded later.
    session_namespace: ?*SessionNamespace = null,
    session_value_bindings: ?*const std.ArrayList(global_sg.GlobalBindingId) = null,

    // Instantiated bodies and cleanup calls have no module pending operation
    // to revisit when a callee gains a transitive reached input. Retain their
    // lexical context until the signatures reach the semantizing fixed point.
    reached_calls: std.ArrayList(ReachedCall) = .empty,
    const ReachedCall = struct {
        callee: global_sg.GlobalFunctionId,
        input: global_sg.GlobalNodeId,
        skip_receiver: bool,
        owner: ?global_sg.GlobalFunctionId,
        visible: []global_sg.GlobalBindingId,
    };

    pub const SessionNamespace = struct {
        modules: std.ArrayList(global_sg.GlobalModuleId) = .empty,
        declarations: std.ArrayList(global_sg.GlobalDeclId) = .empty,
        assumptions: std.ArrayList(global_sg.GlobalBindingId) = .empty,
    };

    pub fn sessionNamespace(self: *Resolver) !*SessionNamespace {
        if (self.session_namespace) |namespace| return namespace;
        const namespace = try self.allocator.create(SessionNamespace);
        namespace.* = .{};
        self.session_namespace = namespace;
        return namespace;
    }

    /// Submission modules retain distinct source identities but belong to one
    /// explicit interactive namespace. Imported modules never join it implicitly.
    pub fn sameDeclarationNamespace(self: *const Resolver, left: usize, right: usize) bool {
        if (self.graph.sameModuleNamespace(@enumFromInt(left), @enumFromInt(right))) return true;
        const namespace = self.session_namespace orelse return false;
        return std.mem.indexOfScalar(global_sg.GlobalModuleId, namespace.modules.items, @enumFromInt(left)) != null and
            std.mem.indexOfScalar(global_sg.GlobalModuleId, namespace.modules.items, @enumFromInt(right)) != null;
    }

    pub fn deinit(self: *Resolver) void {
        self.deinitReachedCalls();
        if (self.session_namespace) |namespace| {
            namespace.modules.deinit(self.allocator);
            namespace.declarations.deinit(self.allocator);
            namespace.assumptions.deinit(self.allocator);
            self.allocator.destroy(namespace);
        }
    }

    pub fn rollbackReachedCalls(self: *Resolver, count: usize) void {
        for (self.reached_calls.items[count..]) |call| self.allocator.free(call.visible);
        self.reached_calls.shrinkRetainingCapacity(count);
    }

    pub fn deinitReachedCalls(self: *Resolver) void {
        self.rollbackReachedCalls(0);
        self.reached_calls.deinit(self.allocator);
    }

    // Instantiation and cleanup can resolve calls before a callee acquires
    // all reached inputs. Keep their lexical environment until signature
    // completion, including calls absent from module pending operations.
    pub fn trackReachedCall(self: *Resolver, callee: global_sg.GlobalFunctionId, input: global_sg.GlobalNodeId, context: reach_context.Context, skip_receiver: bool) !void {
        for (self.reached_calls.items) |call| if (call.input == input and call.callee == callee) return;
        const visible = try self.allocator.alloc(global_sg.GlobalBindingId, context.bindingCount());
        errdefer self.allocator.free(visible);
        for (visible, 0..) |*binding, index| binding.* = context.bindingAt(index);
        try self.reached_calls.append(self.allocator, .{ .callee = callee, .input = input, .skip_receiver = skip_receiver, .owner = context.ownerFunction(), .visible = visible });
    }

    pub fn trackResolvedReachedCall(self: *Resolver, node: global_sg.Node, context: reach_context.Context) !void {
        switch (node.content) {
            .function_call => |call| try self.trackReachedCall(call.callee, call.input, context, false),

            else => {},
        }
    }

    pub fn completeTrackedReachedCalls(self: *Resolver) !bool {
        var changed = false;
        for (self.reached_calls.items) |call| {
            var fields = self.graph.function(call.callee).input;
            if (call.skip_receiver) {
                fields.start += 1;
                fields.len -= 1;
            }
            const literal = self.graph.node(call.input).content.struct_value_literal;
            if (literal.fields.len == fields.len) continue;
            var context = reach_context.Context.fromGlobal(call.visible, call.owner);
            context.global.assumed_fields = literal.assumed_fields;
            if (try self.completeRecordFieldsWithContext(fields, call.input, context)) changed = true;
        }
        return changed;
    }

    pub fn errorTracerField(self: *const Resolver) ?global_sg.Field {
        for (self.graph.functions.items) |function| {
            const owner = self.graph.moduleForDeclaration(function.declaration) orelse continue;
            if (!self.graph.modules.items[@intFromEnum(owner)].is_bundled_core) continue;
            if (!std.mem.eql(u8, self.graph.text(self.graph.declaration(function.declaration).name), "capture_error_tracer")) continue;
            for (self.graph.fields.items[function.input.start..][0..function.input.len]) |field|
                if (std.mem.eql(u8, self.graph.text(field.name), "error_tracer")) return field;
        }
        return null;
    }

    pub fn ensureErrorTracerInput(self: *Resolver, function: global_sg.GlobalFunctionId) !void {
        const field = self.errorTracerField() orelse return;
        _ = try self.propagateReachedDefault(function, field, field.default_value orelse return);
    }

    pub fn resolveExternalTypes(self: *Resolver) !void {
        return self.resolveExternalTypesFrom(0);
    }

    /// Initialize relocated holes in a new module suffix without overwriting
    /// retained slots already materialized by earlier resolution passes.
    pub fn resolveExternalTypesFrom(self: *Resolver, first_module: usize) !void {
        if (first_module > self.modules.len) return error.InvalidSemanticModuleViews;
        for (self.modules[first_module..], first_module..) |*module, module_index| {
            const o = self.offsets[module_index];
            for (0..module_views.typeCount(module)) |raw_type| {
                const local_id: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw_type)));
                const value = try module_views.typeView(module, local_id);
                const external = switch (value) {
                    .external => |id| id,
                    .resolved => continue,
                };
                const reference = module.semantic.external_refs.items[@intFromEnum(external)];
                if (reference.kind != .type or (reference.projection_base != null or reference.computed_type != null)) continue;
                if (reference.module_path == null and reference.generic_arguments == null) {
                    const name = module.text(reference.name);
                    const resolved_builtin = primitives.builtinTypeNamedForTarget(name, self.graph.target.stdTarget());
                    if (resolved_builtin) |builtin_type| {
                        try self.graph.resolveType(self.allocator, globalizer.globalType(o, local_id), .{ .builtin = builtin_type });
                        self.stats.external_types += 1;
                        continue;
                    }
                }
                // Generic external references need parameterized substitution and are
                // intentionally claimed by the generic resolver instead.
                if (reference.generic_arguments != null) continue;
                const target_type = (try self.resolveTypeValue(module_index, reference)) orelse continue;
                const semantic = self.graph.resolvedSemanticType(target_type) orelse continue;
                try self.graph.resolveType(self.allocator, globalizer.globalType(o, local_id), semantic);
                self.stats.external_types += 1;
            }
        }
    }

    pub fn materializeDereferences(self: *Resolver) !bool {
        var changed = false;
        const measurement = if (self.scan_profile) |profile| profile.begin(.dereferences) else null;
        defer if (measurement) |m| m.finish(changed);
        for (self.graph.nodes.items, 0..) |node, raw| {
            if (measurement) |m| m.visit(1);
            switch (node.content) {
                .dereference => |dereference| {
                    const pointer_type = self.graph.nodes.items[@intFromEnum(dereference.pointer)].ty orelse continue;
                    const child = switch (self.graph.types.items[@intFromEnum(pointer_type)]) {
                        .pointer => |pointer| pointer.child,
                        else => continue,
                    };
                    if (node.ty != null and types.equal(self.graph, node.ty.?, child) and types.equal(self.graph, dereference.pointer_type, pointer_type)) continue;
                    var updated = node;
                    updated.ty = child;
                    updated.content.dereference.ty = child;
                    updated.content.dereference.pointer_type = pointer_type;
                    try self.graph.setNode(self.allocator, @enumFromInt(raw), updated);
                    self.stats.dereferences += 1;
                    changed = true;
                },
                else => {},
            }
        }
        return changed;
    }

    pub fn materializeAddresses(self: *Resolver) !bool {
        var changed = false;
        const measurement = if (self.scan_profile) |profile| profile.begin(.addresses) else null;
        defer if (measurement) |m| m.finish(changed);
        for (self.graph.nodes.items, 0..) |node, raw| {
            if (measurement) |m| m.visit(1);
            switch (node.content) {
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
                    try self.graph.setNodeType(self.allocator, @enumFromInt(raw), pointer_type);
                    changed = true;
                },
                else => {},
            }
        }
        return changed;
    }

    pub fn materializeBindingTypes(self: *Resolver) !bool {
        const measurement = if (self.scan_profile) |profile| profile.begin(.binding_types) else null;
        var changed = false;
        defer if (measurement) |m| m.finish(changed);
        changed = try self.inferBindingTypes(measurement);
        if (try self.propagateExpressionTypes(measurement)) changed = true;
        return changed;
    }

    // Initializers can depend on types propagated in a previous round. Only
    // explicitly unresolved bindings participate; declared types stay intact.
    fn inferBindingTypes(self: *Resolver, parent: ?@import("resolution_profile.zig").Profile.Measurement) !bool {
        const measurement = if (self.scan_profile) |profile| profile.begin(.binding_initializers) else null;
        var changed = false;
        defer if (measurement) |m| m.finish(changed);
        for (self.graph.construction.binding_type_resolution.items, 0..) |state, raw| {
            if (measurement) |m| m.visit(1);
            if (parent) |m| m.visit(1);
            if (state != .unresolved) continue;
            const id: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(raw)));
            const binding = &self.graph.bindings.items[raw];
            const initialization = binding.initialization orelse continue;
            if (self.graph.node(initialization).content == .list_literal) {
                const array_type = try self.inferArrayLiteralType(initialization) orelse continue;
                _ = try self.coerceContextualValue(initialization, array_type);
            }
            const inferred = self.graph.nodes.items[@intFromEnum(initialization)].ty orelse continue;
            if (self.graph.isTypeUnresolved(inferred)) continue;
            try self.graph.resolveBindingType(self.allocator, id, inferred);
            self.stats.binding_types += 1;
            changed = true;
        }
        return changed;
    }

    // Keep source/node order: a later expression can observe a type completed
    // earlier in the same sweep. Typed expressions can still be contextualized
    // again, so an existing result type is not a completion certificate.
    fn propagateExpressionTypes(self: *Resolver, parent: ?@import("resolution_profile.zig").Profile.Measurement) !bool {
        const measurement = if (self.scan_profile) |profile| profile.begin(.expression_types) else null;
        var changed = false;
        defer if (measurement) |m| m.finish(changed);
        for (self.graph.nodes.items, 0..) |node, raw| {
            if (measurement) |m| m.visit(1);
            if (parent) |m| m.visit(1);
            switch (node.content) {
                .binding_declaration, .binding_use => |binding_id| {
                    if (self.graph.isBindingTypeUnresolved(binding_id)) continue;
                    const inferred = self.graph.bindings.items[@intFromEnum(binding_id)].ty;
                    // An unresolved type is unequal even to itself in semantic
                    // matching, but writing the same slot cannot advance the
                    // fixed point.
                    if (node.ty != null and (node.ty.? == inferred or types.equal(self.graph, node.ty.?, inferred))) continue;
                    try self.graph.setNodeType(self.allocator, @enumFromInt(raw), inferred);
                    changed = true;
                },
                .value_sequence, .replacement => |block| {
                    const value = self.graph.blocks.items[@intFromEnum(block)].ret_val orelse continue;
                    const inferred = self.graph.node(value).ty orelse continue;
                    if (node.ty != null and (node.ty.? == inferred or types.equal(self.graph, node.ty.?, inferred))) continue;
                    try self.graph.setNodeType(self.allocator, @enumFromInt(raw), inferred);
                    changed = true;
                },
                .move_value => |value| {
                    const inferred = self.graph.nodes.items[@intFromEnum(value)].ty orelse continue;
                    if (node.ty != null and (node.ty.? == inferred or types.equal(self.graph, node.ty.?, inferred))) continue;
                    try self.graph.setNodeType(self.allocator, @enumFromInt(raw), inferred);
                    changed = true;
                },
                .binary_operation => |operation| {
                    var left_ty = self.graph.nodes.items[@intFromEnum(operation.left)].ty orelse continue;
                    var right_ty = self.graph.nodes.items[@intFromEnum(operation.right)].ty orelse continue;
                    // Matching resolved IDs already make coercion a no-op and
                    // the result current. Recheck on every sweep: operands can
                    // receive a different contextual type in a later round.
                    if (node.ty == left_ty and left_ty == right_ty and !self.graph.isTypeUnresolved(left_ty)) continue;
                    try self.coerceIntegerPair(operation.left, &left_ty, operation.right, &right_ty);
                    if (!self.isScalarArithmeticRepresentation(left_ty, right_ty)) continue;
                    if (node.ty != null and (node.ty.? == left_ty or types.equal(self.graph, node.ty.?, left_ty))) continue;
                    try self.graph.setNodeType(self.allocator, @enumFromInt(raw), left_ty);
                    changed = true;
                },
                else => {},
            }
        }
        return changed;
    }

    // Infer only initializers without an expected binding type. Call arguments
    // and annotated values retain contextual typing, including numeric literals.
    // Nested literals are inspected without mutation until the whole array has
    // a single element type, so an incomplete inference cannot fix a child type.
    fn inferArrayLiteralType(self: *Resolver, id: global_sg.GlobalNodeId) error{OutOfMemory}!?global_sg.GlobalTypeId {
        const node = self.graph.node(id);
        if (node.content != .list_literal) {
            const ty = node.ty orelse return null;
            return if (self.graph.isTypeUnresolved(ty)) null else ty;
        }
        const elements = node.content.list_literal.elements;
        if (elements.len == 0) return null;
        var element_type: ?global_sg.GlobalTypeId = null;
        for (self.graph.node_refs.items[elements.start..][0..elements.len]) |element| {
            const ty = try self.inferArrayLiteralType(element) orelse return null;
            if (element_type) |expected| {
                if (!types.equal(self.graph, expected, ty)) return null;
            } else element_type = ty;
        }
        for (self.graph.types.items, 0..) |ty, raw| {
            if (ty == .array and ty.array.length == elements.len and types.equal(self.graph, ty.array.element, element_type.?))
                return @enumFromInt(@as(u32, @intCast(raw)));
        }
        const ty: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .array = .{ .element = element_type.?, .length = elements.len } });
        return ty;
    }

    pub fn defaultStringLiteralType(self: *const Resolver) ?global_sg.GlobalTypeId {
        return self.coreLiteralType("StringView");
    }

    pub fn defaultScalarLiteralType(self: *const Resolver) ?global_sg.GlobalTypeId {
        return self.coreLiteralType("UnicodeScalar");
    }

    fn coreLiteralType(self: *const Resolver, name: []const u8) ?global_sg.GlobalTypeId {
        if (self.graph.indexedDeclarationsNamed(name)) |declarations| {
            for (declarations) |id| if (self.literalDeclarationType(id, name)) |ty| return ty;
            return null;
        }
        for (0..self.graph.declarations.items.len) |raw| {
            if (self.literalDeclarationType(@enumFromInt(raw), name)) |ty| return ty;
        }
        return null;
    }

    fn literalDeclarationType(self: *const Resolver, id: global_sg.GlobalDeclId, name: []const u8) ?global_sg.GlobalTypeId {
        const declaration = self.graph.declaration(id);
        if (declaration.kind != .type or !std.mem.eql(u8, self.graph.text(declaration.name), name)) return null;
        const owner = self.graph.moduleForDeclaration(id) orelse return null;
        if (!self.graph.modules.items[@intFromEnum(owner)].is_bundled_core) return null;
        const ty = declaration.type_id orelse return null;
        if (self.graph.isTypeUnresolved(ty)) return null;
        return ty;
    }

    pub fn materializeTextLiteralTypes(self: *Resolver) !bool {
        const string_ty = self.defaultStringLiteralType();
        const scalar_ty = self.defaultScalarLiteralType();
        var changed = false;
        const measurement = if (self.scan_profile) |profile| profile.begin(.text_literal_types) else null;
        defer if (measurement) |m| m.finish(changed);
        for (self.graph.nodes.items, 0..) |node, raw| {
            if (node.ty != null) continue;
            const ty = switch (node.content) {
                .string_literal => string_ty,
                .char_literal => scalar_ty,
                else => continue,
            } orelse continue;
            try self.graph.setNodeType(self.allocator, @enumFromInt(raw), ty);
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
            .resolve_aggregate_literal => |value| blk: {
                const target = switch (value.target) {
                    .type => |ty| globalizer.globalType(o, ty),
                    .pointee => |pointer| target: {
                        const ty = self.graph.node(globalizer.globalNode(o, pointer)).ty orelse break :blk .deferred;
                        if (self.graph.isTypeUnresolved(ty)) break :blk .deferred;
                        const semantic = self.graph.semanticType(ty);
                        if (semantic != .pointer) break :blk .resolved;
                        break :target semantic.pointer.child;
                    },
                    .element => |array| target: {
                        const ty = self.graph.node(globalizer.globalNode(o, array)).ty orelse break :blk .deferred;
                        if (self.graph.isTypeUnresolved(ty)) break :blk .deferred;
                        break :target types.arrayElement(self.graph, ty) orelse break :blk .resolved;
                    },
                };
                if (self.graph.isTypeUnresolved(target)) break :blk .deferred;
                const id = globalizer.globalNode(o, value.node);
                var context = reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function);
                if (value.assumed_arguments) |arguments|
                    context = context.withAssumedFields(self.graph.node(globalizer.globalNode(o, arguments)).content.struct_value_literal.assumed_fields);
                if (types.arrayElement(self.graph, target) != null) {
                    const completed = self.completeAggregateValue(target, id, context, 0) catch |err| switch (err) {
                        error.DeferredContractInitializer, error.DeferredGenericFunction, error.ComptimeExecutionPending => break :blk .deferred,
                        else => return err,
                    };
                    break :blk resolution.Result.fromBool(completed);
                }
                if (types.fields(self.graph, target) == null) {
                    if (types.isBuiltin(self.graph, target, .Void) or types.arrayLength(self.graph, target) == 0) {
                        _ = try self.coerceContextualValue(id, target);
                        break :blk .resolved;
                    }
                    break :blk .deferred;
                }
                if (self.graph.node(id).content == .list_literal) {
                    // Nonempty lists retain tuple/list diagnostics; only empty
                    // parentheses can supply an omitted record field set.
                    if (self.graph.node(id).content.list_literal.elements.len != 0) break :blk .resolved;
                    try self.graph.setNodeContent(self.allocator, id, .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } });
                }
                if (self.contextualIdentityConflict(id, target)) break :blk .resolved;
                try self.graph.setNodeType(self.allocator, id, target);
                // Leave required-field diagnostics to the shared publication check.
                if (!@import("record_literals.zig").hasRequiredFields(self.graph, id, target)) break :blk .resolved;
                const completed = self.completeRecordValue(target, id, context) catch |err| switch (err) {
                    error.DeferredContractInitializer, error.DeferredGenericFunction, error.ComptimeExecutionPending => break :blk .deferred,
                    else => return err,
                };
                if (!completed) break :blk .deferred;
                break :blk .resolved;
            },
            .resolve_entry_call => |value| blk: {
                const callee = globalizer.globalFunction(o, value.callee);
                const function = self.graph.function(callee);
                if (function.body == null) break :blk .deferred;
                const node = self.graph.node(globalizer.globalNode(o, value.node));
                if (node.content != .function_call or node.content.function_call.callee != callee or !function.flags.is_comptime_entry)
                    return error.InvalidCompileTimeEntryCall;
                break :blk resolution.Result.fromBool(try self.completeRecordFields(function.input, node.content.function_call.input));
            },
            .resolve_value_type => |value| blk: {
                const ty = self.graph.node(globalizer.globalNode(o, value.value)).ty orelse break :blk .deferred;
                if (self.graph.isTypeUnresolved(ty)) break :blk .deferred;
                try self.graph.resolveType(self.allocator, globalizer.globalType(o, value.destination), self.graph.types.items[@intFromEnum(ty)]);
                break :blk .resolved;
            },
            .resolve_call => |value| try self.resolveCall(module_index, module, o, value),
            .resolve_field => |value| resolution.Result.fromBool(try self.resolveField(module, o, value)),
            .resolve_comparison => |value| resolution.Result.fromBool(try self.resolveComparison(module_index, o, value)),
            .resolve_index => |value| try self.resolveIndex(o, value),
            .resolve_dereference => |value| try self.resolveDereference(o, value),
            .resolve_address => |value| try self.resolveAddress(o, value),
            else => .not_applicable,
        };
    }

    /// The module owns the declaration-to-storage relation. Keep this lookup
    /// shared by all compile-time value classifications rather than teaching
    /// each resolver how module-local binding IDs are relocated.
    pub fn declarationBinding(self: *const Resolver, id: global_sg.GlobalDeclId) ?global_sg.GlobalBindingId {
        if (self.graph.declaration(id).kind != .binding) return null;
        const owner = self.graph.moduleForDeclaration(id) orelse return null;
        const module_index = @intFromEnum(owner);
        if (module_index >= self.modules.len) return null;
        const offsets = self.offsets[module_index];
        for (self.modules[module_index].semantic.declaration_bindings.items) |relation| {
            if (globalizer.globalDecl(offsets, relation.declaration) == id)
                return globalizer.globalBinding(offsets, relation.binding);
        }
        return null;
    }

    /// Resolve a type name to its compile-time value. A binding forwards the
    /// initializer's identity; it never acquires nominality from its own name.
    pub fn declarationTypeValue(self: *const Resolver, id: global_sg.GlobalDeclId) ?global_sg.GlobalTypeId {
        const declaration = self.graph.declaration(id);
        if (declaration.family_definition != null or declaration.kind == .contract_type) return null;
        if (declaration.type_id) |ty| return ty;
        const binding = self.declarationBinding(id) orelse return null;
        if (self.graph.isBindingTypeUnresolved(binding)) return null;
        return types.staticTypeBinding(self.graph, binding);
    }

    /// Interactive values keep their original lexical storage. Only static
    /// entities may participate in module-level type/operation definitions.
    pub fn staticSessionBinding(self: *const Resolver, module_index: usize, name: []const u8) ?global_sg.GlobalBindingId {
        const namespace = self.session_namespace orelse return null;
        if (std.mem.indexOfScalar(global_sg.GlobalModuleId, namespace.modules.items, @enumFromInt(module_index)) == null) return null;
        const bindings = self.session_value_bindings orelse return null;
        for (bindings.items) |binding| {
            if (std.mem.eql(u8, self.graph.text(self.graph.binding(binding).name), name) and types.isStaticBinding(self.graph, binding)) return binding;
        }
        return null;
    }

    /// Resolve the visible binding first, then follow its definition value.
    /// Visibility applies to that binding; an exported alias may name a private
    /// underlying definition without changing its lexical context.
    pub fn resolveDefinitionAlias(self: *Resolver, module_index: usize, reference: module_entities.ExternalRef) !?global_sg.DefinitionValue {
        const id = self.resolveDeclaration(module_index, reference, &.{.binding}) catch |err| switch (err) {
            error.UnknownGlobalDeclaration => {
                if (reference.module_path != null) return null;
                const binding = self.staticSessionBinding(module_index, self.modules[module_index].text(reference.name)) orelse return null;
                return types.staticDefinitionBinding(self.graph, binding);
            },
            else => return err,
        };
        const binding = self.declarationBinding(id) orelse return null;
        if (self.graph.isBindingTypeUnresolved(binding)) return null;
        return types.staticDefinitionBinding(self.graph, binding);
    }

    pub fn resolveDefinitionReference(self: *Resolver, module_index: usize, reference: module_entities.ExternalRef, kinds: []const primitives.DeclarationKind) !?global_sg.GlobalFamilyDefinitionId {
        var accepted: [std.meta.fields(primitives.DeclarationKind).len]primitives.DeclarationKind = undefined;
        var count: usize = 0;
        for (kinds) |kind| {
            if (std.mem.indexOfScalar(primitives.DeclarationKind, accepted[0..count], kind) != null) continue;
            accepted[count] = kind;
            count += 1;
        }
        if (std.mem.indexOfScalar(primitives.DeclarationKind, accepted[0..count], .binding) == null) {
            accepted[count] = .binding;
            count += 1;
        }
        const id = self.resolveDeclaration(module_index, reference, accepted[0..count]) catch |err| switch (err) {
            error.UnknownGlobalDeclaration => return null,
            else => return err,
        };
        const declaration = self.graph.declaration(id);
        const definition = if (declaration.kind == .binding) blk: {
            const binding = self.declarationBinding(id) orelse return null;
            if (self.graph.isBindingTypeUnresolved(binding)) return null;
            break :blk (types.staticDefinitionBinding(self.graph, binding) orelse return null).origin;
        } else declaration.family_definition orelse return null;
        const family = self.graph.familyDefinition(definition);
        for (kinds) |kind| if (switch (kind) {
            .type => family.kind == .type,
            .function => family.kind == .function,
            .contract_type => family.kind == .contract,
            else => false,
        }) return definition;
        return null;
    }

    /// Resolve an entity in value position without converting a family into a
    /// concrete Type. Ordinary and specialized bodies share this boundary.
    pub fn resolveEntityValue(self: *Resolver, module_index: usize, reference: module_entities.ExternalRef) !?types.EntityValue {
        if (reference.module_path == null) {
            const name = self.modules[module_index].text(reference.name);
            if (primitives.builtinTypeNamedForTarget(name, self.graph.target.stdTarget())) |kind|
                return .{ .type = try self.builtin(kind) };
        }
        if (try self.resolveDefinitionAlias(module_index, reference)) |value| return .{ .definition = value };
        if (try self.resolveDefinitionReference(module_index, reference, &.{ .type, .contract_type, .function })) |id| {
            return .{ .definition = .{ .origin = id } };
        }
        if (try self.resolveTypeValue(module_index, reference)) |ty| return .{ .type = ty };
        return null;
    }

    pub fn resolveTypeValue(self: *Resolver, module_index: usize, reference: module_entities.ExternalRef) !?global_sg.GlobalTypeId {
        const declaration = self.resolveDeclaration(module_index, reference, &.{ .type, .contract_type, .binding }) catch |err| switch (err) {
            error.UnknownGlobalDeclaration => return null,
            else => return err,
        };
        if (self.graph.declaration(declaration).kind == .contract_type)
            return try types.definitionClass(self.allocator, self.graph, self.graph.declaration(declaration).family_definition.?);
        if (self.graph.declaration(declaration).kind == .binding) {
            if (try self.resolveDefinitionReference(module_index, reference, &.{.contract_type})) |contract|
                return try types.definitionClass(self.allocator, self.graph, contract);
        }
        return self.declarationTypeValue(declaration);
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

    /// Resolve a compiler-synthesized, unqualified call using the same visible-function
    /// resolution rules as a source call. Semantic sugar must not manufacture a
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

    pub fn matchFunctionNamedWithReach(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !FunctionMatch {
        return self.matchVisibleFunction(current_module, name, module_filter, input_node, context);
    }

    fn matchFunctionNamed(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input_node: global_sg.GlobalNodeId,
    ) !FunctionMatch {
        return self.matchVisibleFunction(current_module, name, module_filter, input_node, null);
    }

    pub fn functionSignaturePending(self: *const Resolver, id: global_sg.GlobalFunctionId) bool {
        const function = self.graph.function(id);
        if (function.flags.has_declared_body and
            (function.input_bindings.len < function.input.len or function.output_bindings.len < function.output.len)) return true;
        inline for (.{ "input", "output" }) |direction| {
            if (@field(function, direction ++ "_type")) |ty| {
                const fields = types.fields(self.graph, ty) orelse return true;
                if (fields.len > @field(function, direction).len) return true;
            }
        }
        return false;
    }

    fn matchVisibleFunction(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input_node: global_sg.GlobalNodeId,
        context: ?reach_context.Context,
    ) !FunctionMatch {
        var selected: ?global_sg.GlobalFunctionId = null;
        var saw_deferred = false;
        // A constant alias names the same compile-time function value. Its
        // visibility belongs to the alias; the function's identity stays intact.
        const declarations = try self.graph.declarationsNamed(self.allocator, name);
        for (declarations) |declaration_id| {
            const declaration = self.graph.declaration(declaration_id);
            if (declaration.kind != .binding or !self.declarationVisible(current_module, declaration_id, module_filter)) continue;
            const binding = self.declarationBinding(declaration_id) orelse continue;
            if (self.graph.isBindingTypeUnresolved(binding)) {
                saw_deferred = true;
                continue;
            }
            const definition = types.staticDefinitionBinding(self.graph, binding) orelse continue;
            const family = self.graph.familyDefinition(definition.origin);
            if (family.kind != .function or family.template_index != null) continue;
            const id = self.graph.declaration(self.graph.familyDeclaration(definition.origin)).function_id orelse {
                saw_deferred = true;
                continue;
            };
            if (self.functionSignaturePending(id)) {
                saw_deferred = true;
                continue;
            }
            const applicability = if (context) |reach|
                try self.matchCallInputWithReach(self.graph.function(id).input, input_node, reach)
            else
                self.matchCallInput(self.graph.function(id).input, input_node);
            switch (applicability) {
                .no_match => continue,
                .deferred => saw_deferred = true,
                .applicable => {
                    if (selected != null and selected.? != id) return .ambiguous;
                    selected = id;
                },
            }
        }
        const candidates = try self.graph.functionsNamed(self.allocator, name);
        for (candidates) |id| {
            const function = self.graph.function(id);
            if (!self.declarationVisible(current_module, function.declaration, module_filter)) continue;
            if (self.functionSignaturePending(id)) {
                saw_deferred = true;
                continue;
            }
            const applicability = if (context) |reach|
                try self.matchCallInputWithReach(function.input, input_node, reach)
            else
                self.matchCallInput(function.input, input_node);
            switch (applicability) {
                .no_match => continue,
                .deferred => saw_deferred = true,
                .applicable => {
                    if (selected != null and selected.? != id) return .ambiguous;
                    selected = id;
                },
            }
        }
        if (saw_deferred) return .deferred;
        if (selected) |function| return .{ .function = function };
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

    pub fn familyVisible(self: *const Resolver, current_module: usize, id: global_sg.GlobalFamilyDefinitionId, module_filter: ?global_sg.GlobalModuleId) bool {
        const declaration = self.graph.familyDefinition(id).declaration orelse return false;
        return self.declarationVisible(current_module, declaration, module_filter);
    }

    pub fn declarationVisible(self: *const Resolver, current_module: usize, declaration: global_sg.GlobalDeclId, qualified_module: ?global_sg.GlobalModuleId) bool {
        const owner = self.graph.moduleForDeclaration(declaration) orelse return false;
        const own_module = self.graph.sameModuleNamespace(owner, @enumFromInt(current_module));
        if (self.session_namespace) |namespace| {
            if (qualified_module == null and @intFromEnum(owner) <= current_module and
                std.mem.indexOfScalar(global_sg.GlobalModuleId, namespace.modules.items, @enumFromInt(current_module)) != null and
                std.mem.indexOfScalar(global_sg.GlobalDeclId, namespace.declarations.items, declaration) != null) return true;
        }
        const name = self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name);
        // Bundled core modules form one trusted implementation boundary.
        // Private helpers remain invisible to ordinary user modules.
        const core_peer = self.graph.modules.items[current_module].is_bundled_core and
            self.graph.modules.items[@intFromEnum(owner)].is_bundled_core;
        if (!own_module and !core_peer and std.mem.startsWith(u8, name, "_")) return false;
        if (qualified_module) |wanted| return self.graph.sameModuleNamespace(owner, wanted);
        return own_module or self.graph.modules.items[@intFromEnum(owner)].is_bundled_core;
    }

    pub fn functionOutputType(self: *Resolver, id: global_sg.GlobalFunctionId) !global_sg.GlobalTypeId {
        const function = self.graph.functions.items[@intFromEnum(id)];
        if (function.output.len > 1) if (function.output_type) |ty| return ty;
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
            .virtual_call => |id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                const output = types.fields(self.graph, call.output_type) orelse return false;
                return output.len == 1 and std.mem.eql(u8, self.graph.text(self.graph.fields.items[output.start].name), name);
            },
            .value_sequence, .replacement => |block| return self.isUnpackedOutputField(self.graph.blocks.items[@intFromEnum(block)].ret_val orelse return false, name),
            .binding_use => |id| blk: {
                const binding = self.graph.binding(id);
                // Internal pipe storage preserves single-output labels while
                // ordinary user bindings keep their scalar value semantics.
                if (!std.mem.eql(u8, self.graph.text(binding.name), "#pipe_temporary")) break :blk null;
                return self.isUnpackedOutputField(binding.initialization orelse return false, name);
            } orelse return false,
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
            _ = try self.coerceContextualValue(node, source_field.ty);
            try self.graph.value_fields.append(self.allocator, .{ .name = source_field.name, .value = node });
        }
        const ty = try self.structType(function.input);
        const source = if (nodes.len != 0) self.graph.nodes.items[@intFromEnum(nodes[0])].source else self.syntheticSource();
        return self.appendNode(source, ty, .{ .struct_value_literal = .{
            .fields = .{ .start = start, .len = @intCast(nodes.len) },
        } });
    }

    fn resolveTypeHole(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !resolution.Result {
        if (!self.graph.isTypeUnresolved(globalizer.globalType(o, value.destination))) return .resolved;
        const reference = module.semantic.external_refs.items[@intFromEnum(value.external)];
        if (reference.generic_arguments != null or (reference.projection_base != null or reference.computed_type != null)) return .not_applicable;
        const target = (try self.resolveTypeValue(module_index, reference)) orelse return .deferred;
        const semantic = self.graph.resolvedSemanticType(target) orelse return .deferred;
        try self.graph.resolveType(self.allocator, globalizer.globalType(o, value.destination), semantic);
        self.stats.external_types += 1;
        return .resolved;
    }

    fn resolveCall(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        if (reference.generic_arguments != null or reference.computed_arguments != null) return .not_applicable;
        const input = globalizer.globalNode(o, value.input);
        if (value.callee_value) |local| {
            const pointer = globalizer.globalNode(o, local);
            const ty = self.graph.node(pointer).ty orelse return .deferred;
            if (self.graph.isTypeUnresolved(ty)) return .deferred;
            if (types.definitionValue(self.graph, pointer) != null or types.typeValue(self.graph, pointer) != null) return .not_applicable;
            if (self.graph.semanticType(ty) == .definition or types.isBuiltin(self.graph, ty, .Type)) return .deferred;
            if (!c_abi.isFunctionPointer(self.graph, ty)) return .invalid;
            const declaration = switch (self.graph.resolvedSemanticType(ty).?) {
                .nominal => |id| self.graph.typeDefinition(id),
                else => unreachable,
            };
            const signature = declaration.function_id orelse return .deferred;
            switch (self.matchCallInput(self.graph.function(signature).input, input)) {
                .deferred => return .deferred,
                .no_match => return .invalid,
                .applicable => {},
            }
            const reach = reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function);
            if (!try self.completeCallInputWithReach(signature, input, reach)) return .deferred;
            try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), .{
                .source = self.sourceFor(reference.source, o),
                .ty = try self.functionOutputType(signature),
                .content = .{ .function_call = .{ .callee = signature, .callee_value = pointer, .input = input } },
            });
            self.stats.calls += 1;
            return .resolved;
        }
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
                        try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), .{
                            .source = self.sourceFor(reference.source, o),
                            .ty = try self.builtin(.UIntNative),
                            .content = .{ .int_literal = result },
                        });
                        self.stats.calls += 1;
                        return .resolved;
                    }
                    if (measured.ty) |ty| {
                        if (self.graph.isTypeUnresolved(ty)) {
                            return .deferred;
                        }
                    } else return .deferred;
                }
            }
        }
        if (reference.module_path == null and std.mem.eql(u8, module.text(reference.name), "_zeroed")) {
            const node = (try self.makeZeroed(input, self.sourceFor(reference.source, o))) orelse return .deferred;
            try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), node);
            self.stats.calls += 1;
            return .resolved;
        }
        if (reference.module_path == null and std.mem.eql(u8, module.text(reference.name), "size_of")) {
            const node = (try self.makeSizeOf(input, self.sourceFor(reference.source, o))) orelse return .deferred;
            try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), node);
            self.stats.calls += 1;
            return .resolved;
        }
        if (reference.module_path == null and std.mem.eql(u8, module.text(reference.name), "alignment_of")) {
            const node = (try self.makeAlignmentOf(input, self.sourceFor(reference.source, o))) orelse return .deferred;
            try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), node);
            self.stats.calls += 1;
            return .resolved;
        }
        if (reference.module_path == null and std.mem.eql(u8, module.text(reference.name), "type_of")) {
            const node = (try self.makeTypeOf(input, self.sourceFor(reference.source, o))) orelse return .deferred;
            try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), node);
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
            try self.graph.setNode(self.allocator, target, .{
                .source = self.sourceFor(reference.source, o),
                .ty = void_ty,
                .content = .{ .struct_value_literal = .{
                    .fields = .{ .start = @intCast(self.graph.value_fields.items.len), .len = 0 },
                } },
            });
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
        try self.graph.setNode(self.allocator, target, .{
            .source = self.sourceFor(reference.source, o),
            .ty = if (value.expected_type) |local| globalizer.globalType(o, local) else output,
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        });
        self.stats.calls += 1;
        return .resolved;
    }

    /// Zero construction supports numeric zeros, null callbacks, and arrays;
    /// zero bytes cannot establish references or arbitrary resource invariants.
    pub fn makeZeroed(self: *Resolver, input: global_sg.GlobalNodeId, source: primitives.SourceRef) !?global_sg.Node {
        const ty = self.typeArgument(input, false) orelse return null;
        if (self.graph.isTypeUnresolved(ty)) return null;
        return try self.zeroValue(ty, source);
    }

    fn zeroValue(self: *Resolver, ty: global_sg.GlobalTypeId, source: primitives.SourceRef) anyerror!global_sg.Node {
        if (types.arrayElement(self.graph, ty)) |element| {
            const count: u32 = std.math.cast(u32, types.arrayLength(self.graph, ty).?) orelse return error.TypeSizeOverflow;
            const value = try self.zeroValue(element, source);
            const id: global_sg.GlobalNodeId = @enumFromInt(self.graph.nodes.items.len);
            try self.graph.nodes.append(self.allocator, value);
            const start: u32 = @intCast(self.graph.node_refs.items.len);
            try self.graph.node_refs.appendNTimes(self.allocator, id, count);
            return .{ .source = source, .ty = ty, .content = .{ .array_literal = .{
                .elements = .{ .start = start, .len = count },
                .element_type = element,
                .length = count,
            } } };
        }
        // A callback zero is a null C function pointer, never a data reference.
        if (c_abi.isFunctionPointer(self.graph, ty))
            return .{ .source = source, .ty = ty, .content = .{ .int_literal = 0 } };
        const semantic = self.graph.resolvedSemanticType(ty) orelse return error.InvalidZeroedType;
        const content: @TypeOf(@as(global_sg.Node, undefined).content) = switch (semantic) {
            .builtin => |kind| switch (kind) {
                .Int8, .Int16, .Int32, .Int64, .UInt8, .UInt16, .UInt32, .UInt64, .UIntNative => .{ .int_literal = 0 },
                .Float16, .Float32, .Float64 => .{ .float_literal = 0 },
                else => return error.InvalidZeroedType,
            },
            else => return error.InvalidZeroedType,
        };
        return .{ .source = source, .ty = ty, .content = content };
    }

    fn makeSizeOf(self: *Resolver, input: global_sg.GlobalNodeId, source: primitives.SourceRef) !?global_sg.Node {
        const measured = self.typeArgument(input, true) orelse return null;
        const size = types.sizeOf(self.graph, measured) catch return null;
        return try self.typeInfoLiteral(source, size);
    }

    fn makeAlignmentOf(self: *Resolver, input: global_sg.GlobalNodeId, source: primitives.SourceRef) !?global_sg.Node {
        const measured = self.typeArgument(input, true) orelse return null;
        const alignment = types.alignmentOf(self.graph, measured) catch return null;
        return try self.typeInfoLiteral(source, alignment);
    }

    fn makeTypeOf(self: *Resolver, input: global_sg.GlobalNodeId, source: primitives.SourceRef) !?global_sg.Node {
        const literal = switch (self.graph.node(input).content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            if (!std.mem.eql(u8, self.graph.text(field.name), "value") and !(literal.fields.len == 1 and field.name.len == 0)) continue;
            const value_ty = self.graph.node(field.value).ty orelse return null;
            return .{ .source = source, .ty = try self.builtin(.Type), .content = .{ .type_literal = value_ty } };
        }
        return null;
    }

    fn typeArgument(self: *const Resolver, input: global_sg.GlobalNodeId, allow_value: bool) ?global_sg.GlobalTypeId {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        var measured: ?global_sg.GlobalTypeId = null;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            const unnamed = allow_value and literal.fields.len == 1 and field.name.len == 0;
            if (!std.mem.eql(u8, self.graph.text(field.name), "type") and !unnamed) continue;
            measured = types.typeValue(self.graph, field.value) orelse if (unnamed) self.graph.node(field.value).ty else null;
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
            try self.graph.setNode(self.allocator, target, self.graph.nodes.items[@intFromEnum(source)]);
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
            try self.graph.setNode(self.allocator, target, .{
                .source = .{ .file_index = o.file_base + value.source.file_index, .offset = value.source.offset },
                .ty = pointer,
                .content = .{ .struct_field_access = .{
                    .value = source,
                    .field_name = try self.graph.addString(self.allocator, field_name),
                    .field_index = field_index,
                } },
            });
            self.stats.fields += 1;
            return true;
        }
        const hit = types.findField(self.graph, source_ty, field_name) orelse return false;
        try self.graph.setNode(self.allocator, target, .{
            .source = .{ .file_index = o.file_base + value.source.file_index, .offset = value.source.offset },
            .ty = hit.field.ty,
            .content = .{ .struct_field_access = .{
                .value = source,
                .field_name = try self.graph.addString(self.allocator, module.text(value.field_name)),
                .field_index = hit.index,
            } },
        });
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
        try self.graph.setNode(self.allocator, target, .{
            .source = self.graph.nodes.items[@intFromEnum(pointer)].source,
            .ty = child,
            .content = .{ .dereference = .{
                .pointer = pointer,
                .ty = child,
                .pointer_type = pointer_type,
            } },
        });
        self.stats.dereferences += 1;
        return .resolved;
    }

    fn resolveAddress(self: *Resolver, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const child_node = globalizer.globalNode(o, value.value);
        const child = switch (self.graph.node(child_node).content) {
            .assignment => |assignment| blk: {
                if (self.graph.isBindingTypeUnresolved(assignment.binding)) return .deferred;
                const ty = self.graph.binding(assignment.binding).ty;
                try self.graph.setNodeType(self.allocator, child_node, ty);
                break :blk ty;
            },
            else => self.graph.nodes.items[@intFromEnum(child_node)].ty orelse return .deferred,
        };
        if (self.graph.isTypeUnresolved(child)) return .deferred;
        if (value.collapse_existing_pointer) switch (self.graph.types.items[@intFromEnum(child)]) {
            .pointer => |pointer| if (value.mutability == .read_only or pointer.mutability == .read_write) {
                try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), self.graph.node(child_node));
                return .resolved;
            },
            else => {},
        };
        const pointer_type = try self.pointerType(child, value.mutability);
        const target = globalizer.globalNode(o, value.node);
        try self.graph.setNode(self.allocator, target, .{
            .source = self.graph.nodes.items[@intFromEnum(child_node)].source,
            .ty = pointer_type,
            .content = .{ .address_of = child_node },
        });
        return .resolved;
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
            try self.contextualizeChoiceOperand(module_index, o, right, left_ty)) return false;
        var right_ty = self.graph.nodes.items[@intFromEnum(right)].ty orelse return false;
        // Literal context can arrive after syntaxing when an imported generic
        // supplies the other operand's type. Typed values retain their widths.
        if (!types.equal(self.graph, left_ty, right_ty)) {
            if (self.floatLiteralFits(right, left_ty)) {
                try self.graph.setNodeType(self.allocator, right, left_ty);
                right_ty = left_ty;
            } else if (self.floatLiteralFits(left, right_ty)) {
                try self.graph.setNodeType(self.allocator, left, right_ty);
                left_ty = right_ty;
            }
        }
        try self.coerceIntegerPair(left, &left_ty, right, &right_ty);
        return false;
    }

    fn patchChoiceTagComparison(
        self: *Resolver,
        o: globalizer.Offsets,
        value: anytype,
        choice: global_sg.GlobalNodeId,
        tag: global_sg.GlobalNodeId,
    ) !bool {
        const target = globalizer.globalNode(o, value.node);
        try self.graph.setNode(self.allocator, target, .{
            .source = self.graph.nodes.items[@intFromEnum(choice)].source,
            .ty = try self.builtin(.Bool),
            .content = .{ .comparison = .{
                .operator = value.operator,
                .left = choice,
                .right = tag,
            } },
        });
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
                try self.graph.setNode(self.allocator, node_id, .{
                    .source = .{
                        .file_index = o.file_base + reference.source.file_index,
                        .offset = reference.source.offset,
                    },
                    .ty = try self.builtin(.Int32),
                    .content = .{ .int_literal = types.variantTag(self.graph, choice_ty, hit) },
                });
                return true;
            },
            else => {},
        };
        return false;
    }

    /// A structural constructor has one declared field contract, unlike an
    /// call applicability probe. Supply that contract to still-pending choice literals
    /// before matching; otherwise unrelated choices with the same variant and
    /// payload can make global choice inference ambiguous.
    pub fn contextualizeConstructorChoices(
        self: *Resolver,
        module_index: usize,
        o: globalizer.Offsets,
        expected_fields: global_sg.FieldRange,
        input: global_sg.GlobalNodeId,
    ) !void {
        const literal = switch (self.graph.node(input).content) {
            .struct_value_literal => |literal| literal,
            else => return,
        };
        if (!self.recordFieldNamesMatch(expected_fields, literal)) return;
        for (self.graph.fields.items[expected_fields.start..][0..expected_fields.len], 0..) |field, index| {
            if (self.graph.isTypeUnresolved(field.ty)) continue;
            const supplied = self.callArgument(literal, index, field.name) orelse continue;
            if (self.graph.node(supplied).ty != null) continue;
            _ = try self.contextualizeChoiceOperand(module_index, o, supplied, field.ty);
        }
    }

    fn contextualizeChoiceOperand(self: *Resolver, module_index: usize, o: globalizer.Offsets, node_id: global_sg.GlobalNodeId, expected: global_sg.GlobalTypeId) !bool {
        const module = &self.modules[module_index];
        for (module.semantic.pending_operations.items) |pending| switch (pending) {
            .resolve_choice_literal => |choice| {
                if (globalizer.globalNode(o, choice.node) != node_id) continue;
                if (choice.expected_type != null) return false;
                if (types.variants(self.graph, expected) == null) return false;
                const reference = module.semantic.external_refs.items[@intFromEnum(choice.option)];
                if (types.findVariant(self.graph, expected, module.text(reference.name)) == null) return false;
                try self.graph.setNodeType(self.allocator, node_id, expected);
                return true;
            },
            else => {},
        };
        return false;
    }

    fn resolveIndex(self: *Resolver, o: globalizer.Offsets, value: anytype) !resolution.Result {
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
                    try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), self.graph.node(selected));
                    self.stats.indexes += 1;
                    return .resolved;
                },
                else => {},
            },
            else => {},
        };

        const collection_ty = self.graph.nodes.items[@intFromEnum(collection)].ty orelse return .deferred;
        if (types.arrayElement(self.graph, collection_ty)) |element_ty| {
            if (value.store_value) |local_store|
                try self.contextualizeStoredValue(globalizer.globalNode(o, local_store), element_ty);
            const target = globalizer.globalNode(o, value.node);
            try self.graph.setNode(self.allocator, target, if (value.store_value) |local_store| .{
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
            });
            self.stats.indexes += 1;
            return .resolved;
        }
        // Brackets are a structural operation over native arrays. Library
        // collections expose named functions with their own failure contracts.
        return .not_applicable;
    }

    pub const RecordMatch = enum {
        no_match,
        deferred,
        applicable,
    };

    /// A reached default is available, pending resolution, or absent from
    /// the caller's lexical context.
    pub const ReachedDefaultProbe = enum { unavailable, deferred, available };
    const ReachedAdaptation = enum { direct, address };

    /// Contextual aggregate literals need no type of their own, but computed
    /// leaves must finish resolution before a signature can reject them.
    pub fn callInputHasPendingTypes(self: *const Resolver, input: global_sg.GlobalNodeId) bool {
        const node = self.graph.node(input);
        switch (node.content) {
            .struct_value_literal => |literal| {
                for ([_]@TypeOf(literal.fields){ literal.fields, literal.assumed_fields }) |fields|
                    for (self.graph.value_fields.items[fields.start..][0..fields.len]) |field|
                        if (self.callInputHasPendingTypes(field.value)) return true;
                return false;
            },
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    if (self.callInputHasPendingTypes(element)) return true;
                return false;
            },
            .choice_literal => |literal| return if (literal.payload) |payload| self.callInputHasPendingTypes(payload) else false,
            .int_literal, .float_literal, .char_literal, .bool_literal, .string_literal => return node.ty == null,
            else => return if (node.ty) |ty| self.graph.isTypeUnresolved(ty) else true,
        }
    }

    pub fn matchCallInput(self: *const Resolver, expected_fields: global_sg.FieldRange, input_node: global_sg.GlobalNodeId) RecordMatch {
        const literal = switch (self.graph.node(input_node).content) {
            .struct_value_literal => |value| value,
            else => return .no_match,
        };
        return self.matchRecordFields(expected_fields, literal);
    }

    /// Probe a record without assigning its contextual type or executing defaults.
    /// Calls and ordinary aggregate literals share the same field/value rules.
    pub fn matchRecordFields(self: *const Resolver, expected_fields: global_sg.FieldRange, literal: @FieldType(global_sg.Node.Content, "struct_value_literal")) RecordMatch {
        if (!self.recordFieldNamesMatch(expected_fields, literal)) return .no_match;
        for (0..expected_fields.len) |expected_offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(expected_offset))];
            const supplied = self.callArgument(literal, expected_offset, expected.name);
            if (supplied) |node| {
                if (self.graph.isTypeUnresolved(expected.ty)) {
                    return .deferred;
                }
                const supplied_node = self.graph.nodes.items[@intFromEnum(node)];
                if (self.graph.node(node).ty) |actual| {
                    if (self.graph.isTypeUnresolved(actual)) {
                        return .deferred;
                    }
                    if (!types.equal(self.graph, actual, expected.ty) and
                        !self.valueTypesCompatible(actual, expected.ty) and
                        !types.isBuiltin(self.graph, expected.ty, .Any) and
                        !self.contextualLiteralFits(node, expected.ty)) return .no_match;
                } else if (!self.contextualLiteralFits(node, expected.ty)) switch (supplied_node.content) {
                    .string_literal, .struct_value_literal => return .no_match,
                    else => return .deferred,
                };
            } else if (expected.default_value == null) return .no_match;
        }
        return .applicable;
    }

    pub fn matchCallInputWithReach(
        self: *Resolver,
        expected_fields: global_sg.FieldRange,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !RecordMatch {
        const base = self.matchCallInput(expected_fields, input_node);
        if (base != .applicable) return base;
        const literal = switch (self.graph.nodes.items[@intFromEnum(input_node)].content) {
            .struct_value_literal => |value| value,
            else => return .no_match,
        };
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            if (self.callArgument(literal, offset, expected.name) != null) continue;
            const fallback = expected.default_value orelse return .no_match;
            if (self.graph.nodes.items[@intFromEnum(fallback)].content != .reach_directive) continue;
            switch (try self.probeReachedDefault(
                context,
                expected,
                fallback,
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

    /// Discover a lexical capability's concrete type before a contract's
    /// participant is known. This does not propagate a new caller parameter:
    /// that would infer a participant from an unconstrained missing capability.
    pub fn probeReachedType(self: *Resolver, context: reach_context.Context, default_node: global_sg.GlobalNodeId, deferred: *bool) ?global_sg.GlobalTypeId {
        const reach = self.graph.reaches.items[@intFromEnum(self.graph.node(default_node).content.reach_directive)];
        for (self.graph.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len]) |alternative| {
            if (alternative.segments.len == 0) continue;
            const segments = self.graph.reach_segments.items[alternative.segments.start..][0..alternative.segments.len];
            var index = context.bindingCount();
            while (index > 0) {
                index -= 1;
                const id = context.bindingAt(index);
                const binding = self.graph.binding(id);
                if (!std.mem.eql(u8, self.graph.text(binding.name), self.graph.text(segments[0]))) continue;
                if (self.graph.isBindingTypeUnresolved(id)) {
                    deferred.* = true;
                    return null;
                }
                var ty = binding.ty;
                for (segments[1..]) |segment| {
                    const field = self.reachedField(ty, self.graph.text(segment)) orelse return null;
                    ty = field.hit.field.ty;
                }
                if (self.graph.isTypeUnresolved(ty)) {
                    deferred.* = true;
                    return null;
                }
                return ty;
            }
        }
        return null;
    }

    pub fn probeReachedDefault(
        self: *Resolver,
        context: reach_context.Context,
        expected_field: global_sg.Field,
        default_node: global_sg.GlobalNodeId,
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
                if (self.graph.isBindingTypeUnresolved(binding_id)) {
                    saw_deferred = true;
                    continue;
                }
                if (self.graph.isTypeUnresolved(binding.ty)) {
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
                    current_ty = step.hit.field.ty;
                }
                if (!valid) continue;
                if (self.graph.isTypeUnresolved(current_ty)) {
                    saw_deferred = true;
                    continue;
                }
                if (self.reachedAdaptation(current_ty, expected_field.ty) != null)
                    return .available;
            }
        }

        const owner_id = context.ownerFunction() orelse
            return if (saw_deferred) .deferred else .unavailable;
        const owner = self.graph.functions.items[@intFromEnum(owner_id)];
        const owner_name = self.graph.text(self.graph.declarations.items[@intFromEnum(owner.declaration)].name);
        if (std.mem.eql(u8, owner_name, "main") and !std.mem.eql(u8, self.graph.text(expected_field.name), "error_tracer"))
            return if (saw_deferred) .deferred else .unavailable;

        for (self.graph.fields.items[owner.input.start..][0..owner.input.len]) |field| {
            if (!std.mem.eql(u8, self.graph.text(field.name), self.graph.text(expected_field.name))) continue;
            if (self.graph.isTypeUnresolved(field.ty)) {
                return .deferred;
            }
            if (self.graph.isTypeUnresolved(expected_field.ty)) {
                return .deferred;
            }
            return if (self.reachedTypesCompatible(field.ty, expected_field.ty) or
                self.reachedTypesCompatible(expected_field.ty, field.ty))
                .available
            else
                .unavailable;
        }

        // Completion may propagate a missing reach parameter into a non-main
        // caller. Ranking can acknowledge that possibility without mutating
        // the caller while probing candidates.
        return .available;
    }

    fn reachedTypesCompatible(
        self: *const Resolver,
        actual: global_sg.GlobalTypeId,
        expected: global_sg.GlobalTypeId,
    ) bool {
        if (types.equal(self.graph, actual, expected) or self.valueTypesCompatible(actual, expected))
            return true;
        return false;
    }

    fn reachedAdaptation(
        self: *const Resolver,
        actual: global_sg.GlobalTypeId,
        expected: global_sg.GlobalTypeId,
    ) ?ReachedAdaptation {
        if (self.reachedTypesCompatible(actual, expected))
            return .direct;

        const expected_pointer = switch (self.graph.types.items[@intFromEnum(expected)]) {
            .pointer => |pointer| pointer,
            else => return null,
        };
        if (self.reachedTypesCompatible(actual, expected_pointer.child))
            return .address;
        return null;
    }

    pub fn recordFieldNamesMatch(self: *const Resolver, expected_fields: global_sg.FieldRange, literal: anytype) bool {
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

    pub fn valueTypesCompatible(self: *const Resolver, actual: global_sg.GlobalTypeId, expected: global_sg.GlobalTypeId) bool {
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
            .virtual => |contract_type| types.equal(self.graph, contract_type, expected_pointer.child),
            else => false,
        };
    }

    fn callArgument(self: *const Resolver, literal: anytype, expected_offset: usize, expected_name: primitives.StringRange) ?global_sg.GlobalNodeId {
        return self.recordFieldValue(literal, expected_offset, self.graph.text(expected_name));
    }

    pub fn recordFieldValue(self: *const Resolver, literal: anytype, expected_offset: usize, expected_name: []const u8) ?global_sg.GlobalNodeId {
        if (@import("record_literals.zig").suppliedField(self.graph, literal, expected_offset, expected_name)) |value| return value;
        for (self.graph.value_fields.items[literal.assumed_fields.start..][0..literal.assumed_fields.len]) |assumed| {
            if (std.mem.eql(u8, self.graph.text(assumed.name), expected_name)) return assumed.value;
        }
        return null;
    }

    fn completeCallInput(self: *Resolver, function_id: global_sg.GlobalFunctionId, input_node: global_sg.GlobalNodeId) !bool {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        return self.completeRecordFields(function.input, input_node);
    }

    fn completeCallInputWithReach(
        self: *Resolver,
        function_id: global_sg.GlobalFunctionId,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !bool {
        return self.completeRecordFieldsWithContext(
            self.graph.functions.items[@intFromEnum(function_id)].input,
            input_node,
            context,
        );
    }

    fn instantiateCapturedExpression(self: *Resolver, fallback: global_sg.GlobalNodeId, context: reach_context.Context) anyerror!?global_sg.GlobalNodeId {
        const defaults = self.captured_expressions orelse return null;
        return defaults.instantiate(defaults.context, self.graph.node(fallback).content.captured_expression, context) catch |err| switch (err) {
            error.DeferredGenericFunction => null,
            else => return err,
        };
    }

    fn completeAggregateValue(self: *Resolver, target: global_sg.GlobalTypeId, node: global_sg.GlobalNodeId, context: reach_context.Context, depth: usize) anyerror!bool {
        if (depth > 64) return false;
        if (types.arrayElement(self.graph, target)) |element| {
            const content = self.graph.node(node).content;
            const elements = switch (content) {
                .list_literal => |literal| literal.elements,
                .array_literal => |literal| literal.elements,
                else => return true,
            };
            if (elements.len != types.arrayLength(self.graph, target).?) return true;
            // Default instantiation can grow the node-reference pool.
            for (0..elements.len) |index| {
                const child = self.graph.node_refs.items[elements.start + index];
                if (!try self.completeAggregateValue(element, child, context, depth + 1)) return false;
            }
            try self.graph.setNodeContent(self.allocator, node, .{ .array_literal = .{ .elements = elements, .element_type = element, .length = elements.len } });
            try self.graph.setNodeType(self.allocator, node, target);
            return true;
        }
        const content = self.graph.node(node).content;
        if (content == .list_literal and content.list_literal.elements.len == 0 and types.fields(self.graph, target) != null)
            try self.graph.setNodeContent(self.allocator, node, .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } });
        if (self.graph.node(node).content == .struct_value_literal) {
            if (self.contextualIdentityConflict(node, target)) return true;
            if (!@import("record_literals.zig").hasRequiredFields(self.graph, node, target)) {
                try self.graph.setNodeType(self.allocator, node, target);
                return true;
            }
            return self.completeRecordValue(target, node, context);
        }
        _ = try self.coerceContextualValue(node, target);
        return true;
    }

    pub fn completeRecordValue(self: *Resolver, target: global_sg.GlobalTypeId, node: global_sg.GlobalNodeId, context: reach_context.Context) anyerror!bool {
        if (self.contextualIdentityConflict(node, target)) return false;
        const fields = types.fields(self.graph, target) orelse return false;
        if (types.isCUnion(self.graph, target)) {
            _ = try self.coerceContextualValue(node, target);
            return true;
        }
        if (!try self.completeRecordFieldsWithContext(fields, node, context)) return false;
        try self.graph.setNodeType(self.allocator, node, target);
        return true;
    }

    pub fn completeRecordFields(self: *Resolver, expected_fields: global_sg.FieldRange, input_node: global_sg.GlobalNodeId) !bool {
        return self.completeRecordFieldsWithContext(expected_fields, input_node, reach_context.Context.fromGlobal(&.{}, null));
    }

    pub fn completeRecordFieldsWithContext(
        self: *Resolver,
        expected_fields: global_sg.FieldRange,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) anyerror!bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input_node)].content) {
            .struct_value_literal => |value| value,
            else => return false,
        };
        if (!self.recordFieldNamesMatch(expected_fields, literal)) return false;
        var transaction = self.graph.beginTransaction(self.allocator);
        defer transaction.deinit();
        var effects = if (self.captured_expressions) |defaults|
            defaults.checkpoint(defaults.context)
        else
            null;
        const calls = self.reached_calls.items.len;
        var published = false;
        defer if (!published) {
            self.rollbackReachedCalls(calls);
            transaction.rollback();
            if (effects) |checkpoint| self.captured_expressions.?.rollback(self.captured_expressions.?.context, checkpoint);
        };
        errdefer |err| {
            if (err == error.ComptimeExecutionPending)
                if (effects) |*checkpoint| {
                    checkpoint.execution_requests = null;
                };
        }
        var values: std.ArrayList(global_sg.ValueField) = .empty;
        defer values.deinit(self.allocator);
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            var node = self.callArgument(literal, offset, expected.name);
            if (node == null) {
                const fallback = expected.default_value orelse return false;
                if (self.graph.nodes.items[@intFromEnum(fallback)].content == .reach_directive) {
                    node = try self.resolveReachedDefault(context, fallback, expected.ty);
                } else if (self.graph.node(fallback).content == .captured_expression) {
                    node = try self.instantiateCapturedExpression(fallback, if (literal.assumed_fields.len != 0) context.withAssumedFields(literal.assumed_fields) else context);
                } else {
                    node = fallback;
                }
                if (node == null and self.graph.nodes.items[@intFromEnum(fallback)].content == .reach_directive)
                    node = try self.propagateReachedDefault(
                        context.ownerFunction(),
                        expected,
                        fallback,
                    );
            }
            const value = node orelse return false;
            // Defaults follow the same storage context as explicit values.
            // Retain integer widths even for invalid literals so the ordinary
            // range checker diagnoses them before either backend emits code.
            try self.contextualizeStoredValue(value, expected.ty);
            if (self.graph.node(value).content == .struct_value_literal) {
                if (types.fields(self.graph, expected.ty) != null)
                    if (!try self.completeRecordValue(expected.ty, value, context)) return false;
            }
            try values.append(self.allocator, .{ .name = expected.name, .value = value });
        }
        const ty = try self.structType(expected_fields);
        const start: u32 = @intCast(self.graph.value_fields.items.len);
        try self.graph.value_fields.appendSlice(self.allocator, values.items);
        var completed = self.graph.node(input_node);
        completed.ty = ty;
        completed.content.struct_value_literal = .{
            .fields = .{ .start = start, .len = expected_fields.len },
            .assumed_fields = literal.assumed_fields,
        };
        try self.graph.setNode(self.allocator, input_node, completed);
        transaction.commit();
        published = true;
        return true;
    }

    /// A local `reach` declaration uses the same lexical lookup and reference
    /// adaptation as an omitted reached call argument.
    pub fn resolveReachedBinding(
        self: *Resolver,
        context: reach_context.Context,
        reach_node: global_sg.GlobalNodeId,
        binding: global_sg.GlobalBindingId,
    ) !?global_sg.GlobalNodeId {
        const declared = self.graph.bindings.items[@intFromEnum(binding)];
        if (try self.resolveReachedDefault(context, reach_node, declared.ty)) |node|
            return node;
        return self.propagateReachedDefault(context.ownerFunction(), .{
            .name = declared.name,
            .ty = declared.ty,
            .source = declared.source,
            .default_value = reach_node,
        }, reach_node);
    }

    fn resolveReachedDefault(
        self: *Resolver,
        context: reach_context.Context,
        default_node: global_sg.GlobalNodeId,
        expected: global_sg.GlobalTypeId,
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
                    current_ty = step.hit.field.ty;
                }
                if (self.graph.isTypeUnresolved(current_ty)) valid = false;
                if (!valid) continue;
                const adaptation = self.reachedAdaptation(current_ty, expected) orelse continue;

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
                        .ty = hit.field.ty,
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

    fn propagateReachedDefault(
        self: *Resolver,
        owner_id: ?global_sg.GlobalFunctionId,
        reached_field: global_sg.Field,
        default_node: global_sg.GlobalNodeId,
    ) !?global_sg.GlobalNodeId {
        const resolved_owner = owner_id orelse return null;
        const owner = self.graph.function(resolved_owner);
        const owner_name = self.graph.text(self.graph.declarations.items[@intFromEnum(owner.declaration)].name);
        if (std.mem.eql(u8, owner_name, "main") and !std.mem.eql(u8, self.graph.text(reached_field.name), "error_tracer")) return null;

        for (0..owner.input.len) |offset| {
            const field = self.graph.fields.items[owner.input.start + @as(u32, @intCast(offset))];
            if (!std.mem.eql(u8, self.graph.text(field.name), self.graph.text(reached_field.name))) continue;
            if (!self.reachedTypesCompatible(field.ty, reached_field.ty) and
                !self.reachedTypesCompatible(reached_field.ty, field.ty)) return null;
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

        // A host entry cannot acquire capabilities by extending its C ABI.
        if (owner.flags.is_c_abi) return null;

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
        var completed = owner;
        completed.input = .{ .start = field_start, .len = old_input.len + 1 };
        completed.input_bindings = .{ .start = binding_start, .len = old_bindings.len + 1 };
        try self.graph.setFunction(self.allocator, resolved_owner, completed);

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
        // Interning preserves type identity, including defaults carried by
        // internal signature records; callable compatibility is weaker.
        for (self.graph.types.items, 0..) |ty, raw| {
            if (self.profile_io != null) self.stats.pointer_type_candidates += 1;
            switch (ty) {
                .pointer => |pointer| if (pointer.mutability == mutability and types.identityEqual(self.graph, pointer.child, child))
                    return @enumFromInt(@as(u32, @intCast(raw))),
                else => {},
            }
        }
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .pointer = .{ .child = child, .mutability = mutability } });
        return id;
    }

    pub fn isScalarArithmeticRepresentation(self: *Resolver, a: global_sg.GlobalTypeId, b: global_sg.GlobalTypeId) bool {
        if (!types.equal(self.graph, a, b)) return false;
        return switch (types.representation(self.graph, a) orelse return false) {
            .builtin => |value| switch (value) {
                .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64, .Float16, .Float32, .Float64 => true,
                else => false,
            },
            else => false,
        };
    }

    pub fn contextualizeArithmeticPair(self: *Resolver, operands: []const global_sg.GlobalNodeId) !void {
        var left = self.graph.node(operands[0]).ty orelse return;
        var right = self.graph.node(operands[1]).ty orelse return;
        if (self.floatLiteralFits(operands[0], right)) {
            try self.graph.setNodeType(self.allocator, operands[0], right);
            left = right;
        } else if (self.floatLiteralFits(operands[1], left)) {
            try self.graph.setNodeType(self.allocator, operands[1], left);
            right = left;
        }
        try self.coerceIntegerPair(operands[0], &left, operands[1], &right);
    }

    pub fn coerceIntegerPair(
        self: *Resolver,
        left: global_sg.GlobalNodeId,
        left_ty: *global_sg.GlobalTypeId,
        right: global_sg.GlobalNodeId,
        right_ty: *global_sg.GlobalTypeId,
    ) !void {
        if (types.equal(self.graph, left_ty.*, right_ty.*)) return;
        // Default integer literals follow the typed operand, including typed
        // constants produced by compile-time operations such as size_of.
        if (types.isBuiltin(self.graph, right_ty.*, .Int32) and try self.coerceIntegerLiteral(right, left_ty.*)) {
            right_ty.* = left_ty.*;
            return;
        }
        if (try self.coerceIntegerLiteral(left, right_ty.*)) {
            left_ty.* = right_ty.*;
        } else if (try self.coerceIntegerLiteral(right, left_ty.*)) {
            right_ty.* = left_ty.*;
        }
    }

    fn coerceIntegerLiteral(self: *Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) !bool {
        if (!self.integerLiteralFits(node, target)) return false;
        try self.graph.setNodeType(self.allocator, node, target);
        return true;
    }

    pub fn floatLiteralFits(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        if (self.graph.node(node).content != .float_literal) return false;
        return switch (types.representation(self.graph, target) orelse return false) {
            .builtin => |value| value == .Float16 or value == .Float32 or value == .Float64,
            else => false,
        };
    }

    fn contextualIdentityConflict(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        // Text literals receive StringView as their default type during
        // resolution. Their spelling can still be contextualized as C text;
        // a binding containing a StringView is not a literal and stays nominal.
        if (self.graph.node(node).content == .string_literal) return false;
        const actual = self.graph.node(node).ty orelse return false;
        return types.hasNominalIdentity(self.graph, actual) and !types.equal(self.graph, actual, target);
    }

    pub fn contextualLiteralFits(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        if (self.contextualIdentityConflict(node, target)) return false;
        if (self.integerLiteralFits(node, target) or self.floatLiteralFits(node, target)) return true;
        if (self.pendingChoiceLiteralFits(node, target)) return true;
        switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .bool_literal => return if (types.representation(self.graph, target)) |represented| represented == .builtin and represented.builtin == .Bool else false,
            .string_literal => return switch (self.graph.types.items[@intFromEnum(target)]) {
                .pointer => |pointer| pointer.mutability == .read_only and types.isBuiltin(self.graph, pointer.child, primitives.builtinTypeNamedForTarget("CChar", self.graph.target.stdTarget()).?),
                else => false,
            },
            .struct_value_literal => |literal| return self.contextualStructLiteralFits(literal, target),
            .list_literal => |literal| return self.contextualListLiteralFits(literal, target),
            else => return false,
        }
    }

    fn pendingChoiceLiteralFits(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        if (self.graph.node(node).ty != null or types.variants(self.graph, target) == null) return false;
        // Probe the candidate's contract without assigning it to the literal.
        // Shared variant names must not depend on unrelated choices elsewhere
        // in core; only completion of the selected call commits the context.
        const index = @intFromEnum(node);
        for (self.modules, self.offsets) |module, o| {
            if (index < o.node_base or index - o.node_base >= module.semantic.nodes.items.len) continue;
            for (module.semantic.pending_operations.items) |pending| switch (pending) {
                .resolve_choice_literal => |choice| {
                    if (globalizer.globalNode(o, choice.node) != node or choice.expected_type != null) continue;
                    const reference = module.semantic.external_refs.items[@intFromEnum(choice.option)];
                    const hit = types.findVariant(self.graph, target, module.text(reference.name)) orelse return false;
                    const payload = choice.payload orelse return hit.variant.payload_type == null;
                    const expected = hit.variant.payload_type orelse return false;
                    const supplied = globalizer.globalNode(o, payload);
                    if (self.graph.node(supplied).ty) |actual| {
                        if (types.equal(self.graph, actual, expected) or self.valueTypesCompatible(actual, expected)) return true;
                    }
                    return self.contextualLiteralFits(supplied, expected);
                },
                else => {},
            };
        }
        return false;
    }

    fn contextualListLiteralFits(self: *const Resolver, literal: anytype, target: global_sg.GlobalTypeId) bool {
        if (literal.elements.len == 0) {
            if (types.isBuiltin(self.graph, target, .Void)) return true;
            if (types.fields(self.graph, target)) |fields| {
                for (self.graph.fields.items[fields.start..][0..fields.len]) |field| if (field.default_value == null) return false;
                return true;
            }
        }
        const element = types.arrayElement(self.graph, target) orelse return false;
        const length = types.arrayLength(self.graph, target) orelse return false;
        if (literal.elements.len != length) return false;
        for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |item| {
            const node = self.graph.node(item);
            if (node.ty) |actual| {
                if (types.equal(self.graph, actual, element) or self.valueTypesCompatible(actual, element) or
                    self.contextualLiteralFits(item, element)) continue;
            } else if (self.contextualLiteralFits(item, element)) continue;
            return false;
        }
        return true;
    }

    fn contextualStructLiteralFits(self: *const Resolver, literal: anytype, target: global_sg.GlobalTypeId) bool {
        if (literal.fields.len == 0) {
            if (types.isBuiltin(self.graph, target, .Void)) return true;
            if (types.arrayLength(self.graph, target)) |length| return length == 0;
        }
        const expected_fields = types.fields(self.graph, target) orelse return false;
        return self.matchRecordFields(expected_fields, literal) == .applicable;
    }

    fn coerceContextualLiteral(self: *Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) !bool {
        if (!self.contextualLiteralFits(node, target)) return false;
        try self.graph.setNodeType(self.allocator, node, target);
        return true;
    }

    pub fn contextualizeStoredValue(self: *Resolver, value: global_sg.GlobalNodeId, element: global_sg.GlobalTypeId) !void {
        _ = try self.coerceContextualValue(value, element);
        // Even an out-of-range integer literal carries its destination type
        // into Safety, which diagnoses the range before codegen can emit it.
        if (self.graph.node(value).content == .int_literal) switch (types.representation(self.graph, element) orelse return) {
            .builtin => |kind| if (primitives.integerRange(kind, self.graph.target.stdTarget()) != null) {
                try self.graph.setNodeType(self.allocator, value, element);
            },
            else => {},
        };
    }

    pub fn coerceContextualValue(self: *Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) !bool {
        if (self.contextualIdentityConflict(node, target)) return false;
        // Scalar literals have one nominal identity. Wait for bundled core to
        // resolve it rather than adopting an arbitrary early expected type.
        if (self.graph.node(node).content == .char_literal) return false;
        if (self.graph.node(node).content == .list_literal) {
            // A contextual type does not establish a literal's shape. Keep
            // incompatible lists untyped so diagnostics can inspect their elements.
            if (!self.contextualListLiteralFits(self.graph.node(node).content.list_literal, target)) return false;
            const literal = self.graph.node(node).content.list_literal;
            // Parentheses have no inherent element/record type. Normalize an
            // empty literal only after its destination establishes the shape.
            if (literal.elements.len == 0 and types.arrayElement(self.graph, target) == null) {
                try self.graph.setNodeContent(self.allocator, node, .{ .struct_value_literal = .{
                    .fields = .{ .start = 0, .len = 0 },
                } });
                try self.graph.setNodeType(self.allocator, node, target);
                return true;
            }
            const element = types.arrayElement(self.graph, target) orelse return false;
            for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |item|
                _ = try self.coerceContextualValue(item, element);
            try self.graph.setNodeContent(self.allocator, node, .{ .array_literal = .{
                .elements = literal.elements,
                .element_type = element,
                .length = literal.elements.len,
            } });
            try self.graph.setNodeType(self.allocator, node, target);
            return true;
        }
        if (self.graph.nodes.items[@intFromEnum(node)].content != .struct_value_literal and
            try self.coerceContextualLiteral(node, target)) return true;
        const current = self.graph.nodes.items[@intFromEnum(node)].ty;
        const literal = switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .struct_value_literal => |value| value,
            else => {
                if (current == null) {
                    try self.graph.setNodeType(self.allocator, node, target);
                    return true;
                }
                return false;
            },
        };
        // Void is represented by an empty aggregate value, but unlike normal
        // structural types it has no field range. Context must therefore
        // materialize the empty literal directly instead of asking for fields.
        if (types.isBuiltin(self.graph, target, .Void) and literal.fields.len == 0) {
            try self.graph.setNodeType(self.allocator, node, target);
            return true;
        }
        // Empty parentheses also represent a zero-length array when the
        // destination supplies its element type.
        if (literal.fields.len == 0 and types.arrayLength(self.graph, target) == 0) {
            try self.graph.setNodeContent(self.allocator, node, .{ .array_literal = .{
                .elements = .{ .start = 0, .len = 0 },
                .element_type = types.arrayElement(self.graph, target).?,
                .length = 0,
            } });
            try self.graph.setNodeType(self.allocator, node, target);
            return true;
        }
        const expected_fields = types.fields(self.graph, target) orelse return false;
        // Context supplies identity before missing-field diagnostics run. The
        // shared record-literal publication check rejects incomplete values;
        // contextual tagging alone does not establish initialization.
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            const actual = self.callArgument(literal, offset, expected.name) orelse continue;
            _ = try self.coerceContextualValue(actual, expected.ty);
        }
        _ = try self.normalizeNamedStructLiteral(node, target);
        try self.graph.setNodeType(self.allocator, node, target);
        return true;
    }

    fn normalizeNamedStructLiteral(self: *Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) anyerror!bool {
        const literal = self.graph.node(node).content.struct_value_literal;
        const expected_fields = types.fields(self.graph, target) orelse return false;
        if (literal.fields.len > expected_fields.len) return false;
        var ordered = literal.fields.len == expected_fields.len;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |field, offset| {
            const expected = self.graph.fields.items[expected_fields.start + offset];
            if (!std.mem.eql(u8, self.graph.text(field.name), self.graph.text(expected.name))) {
                ordered = false;
                break;
            }
        }
        if (ordered) return false;
        // Defaults need the caller's lexical capabilities. Context-free type
        // coercion only orders complete records; completeRecordValue performs
        // missing-field completion with its checked reach context.
        if (literal.fields.len != expected_fields.len) return false;
        var values: std.ArrayList(global_sg.ValueField) = .empty;
        defer values.deinit(self.allocator);
        for (self.graph.fields.items[expected_fields.start..][0..expected_fields.len]) |expected| {
            const value = for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
                if (std.mem.eql(u8, self.graph.text(field.name), self.graph.text(expected.name))) break field.value;
            } else return false;
            try values.append(self.allocator, .{ .name = expected.name, .value = value });
        }
        const start: u32 = @intCast(self.graph.value_fields.items.len);
        try self.graph.value_fields.appendSlice(self.allocator, values.items);
        var completed = self.graph.node(node);
        completed.ty = target;
        completed.content.struct_value_literal.fields = .{ .start = start, .len = expected_fields.len };
        try self.graph.setNode(self.allocator, node, completed);
        return true;
    }

    // A record can receive its contextual type before calls/binding uses in
    // nested lists have resolved. The parent's type alone does not establish
    // that every child has been normalized into its executable value shape.
    // Retry only when an unfinished literal can now make semantic progress.
    fn contextualAggregateNeedsCompletion(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        return switch (self.graph.node(node).content) {
            .list_literal => |literal| self.contextualListLiteralFits(literal, target),
            .struct_value_literal => |literal| blk: {
                const fields = types.fields(self.graph, target) orelse break :blk false;
                for (self.graph.fields.items[fields.start..][0..fields.len], 0..) |field, index| {
                    const child = self.callArgument(literal, index, field.name) orelse continue;
                    if (self.contextualAggregateNeedsCompletion(child, field.ty)) break :blk true;
                }
                break :blk false;
            },
            else => false,
        };
    }

    pub fn materializeAssignmentValues(self: *Resolver) !bool {
        var changed = false;
        const measurement = if (self.scan_profile) |profile| profile.begin(.assignment_values) else null;
        defer if (measurement) |m| m.finish(changed);
        // Specialized generic bodies can already carry their contextual type.
        // Normalize their literals too, even without an assignment type change.
        const count = self.graph.nodes.items.len;
        var index: usize = 0;
        while (index < count) : (index += 1) {
            if (measurement) |m| m.visit(1);
            const node = self.graph.nodes.items[index];
            if (node.content != .struct_value_literal) continue;
            const target = node.ty orelse continue;
            if (try self.normalizeNamedStructLiteral(@enumFromInt(index), target)) changed = true;
        }
        for (self.graph.bindings.items, 0..) |binding, raw| {
            if (measurement) |m| m.visit(1);
            if (self.graph.isBindingTypeUnresolved(@enumFromInt(@as(u32, @intCast(raw))))) continue;
            const initialization = binding.initialization orelse continue;
            const current = self.graph.node(initialization).ty;
            if (current == null or (!types.equal(self.graph, current.?, binding.ty) and self.contextualLiteralFits(initialization, binding.ty)) or
                self.contextualAggregateNeedsCompletion(initialization, binding.ty))
                if (try self.coerceContextualValue(initialization, binding.ty)) {
                    changed = true;
                };
        }
        for (self.graph.nodes.items) |node| {
            if (measurement) |m| m.visit(1);
            const assignment = switch (node.content) {
                .assignment => |value| value,
                .pointer_assignment => |value| {
                    const pointer_ty = self.graph.node(value.pointer).ty orelse continue;
                    const pointer = switch (self.graph.semanticType(pointer_ty)) {
                        .pointer => |item| item,
                        else => continue,
                    };
                    const current = self.graph.node(value.value).ty;
                    if (current == null or (!types.equal(self.graph, current.?, pointer.child) and self.contextualLiteralFits(value.value, pointer.child)) or
                        self.contextualAggregateNeedsCompletion(value.value, pointer.child))
                        if (try self.coerceContextualValue(value.value, pointer.child)) {
                            changed = true;
                        };
                    continue;
                },
                else => continue,
            };
            if (self.graph.isBindingTypeUnresolved(assignment.binding)) continue;
            const current = self.graph.node(assignment.value).ty;
            const expected = self.graph.binding(assignment.binding).ty;
            if (current != null and (types.equal(self.graph, current.?, expected) or !self.contextualLiteralFits(assignment.value, expected)) and
                !self.contextualAggregateNeedsCompletion(assignment.value, expected)) continue;
            // Assignment destinations supply the contextual shape of anonymous
            // aggregates before summary inference and codegen consume them.
            if (try self.coerceContextualValue(assignment.value, self.graph.binding(assignment.binding).ty)) changed = true;
        }
        return changed;
    }

    fn integerLiteralFits(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
        const value = switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .int_literal => |number| number,
            else => return false,
        };
        const fits = switch (types.representation(self.graph, target) orelse return false) {
            .builtin => |builtin_type| switch (builtin_type) {
                .Int8 => value >= std.math.minInt(i8) and value <= std.math.maxInt(i8),
                .Int16 => value >= std.math.minInt(i16) and value <= std.math.maxInt(i16),
                .Int32 => value >= std.math.minInt(i32) and value <= std.math.maxInt(i32),
                .Int64 => value >= std.math.minInt(i64) and value <= std.math.maxInt(i64),
                .UIntNative => value >= 0 and value <= std.math.maxInt(usize),
                .UInt8 => value >= 0 and value <= std.math.maxInt(u8),
                .UInt16 => value >= 0 and value <= std.math.maxInt(u16),
                .UInt32 => value >= 0 and value <= std.math.maxInt(u32),
                .UInt64 => value >= 0 and value <= std.math.maxInt(u64),
                else => false,
            },
            else => false,
        };
        return fits;
    }

    // Ordinary and specialized bodies use the same scalar comparison rules.
    // Aggregate equality belongs to operator resolution, not LLVM's icmp.
    pub fn isDirectComparison(
        self: *Resolver,
        operator: primitives.ComparisonOperator,
        left: global_sg.GlobalTypeId,
        right: global_sg.GlobalTypeId,
    ) bool {
        // TODO: Diagnose unsupported choice-value comparisons explicitly;
        // comparisons against bare variant tags are resolved separately.
        return self.isBuiltinComparable(left, right) or
            ((operator == .equal or operator == .not_equal) and
                self.isTagOrForeignEqualityRepresentation(left, right));
    }

    pub fn isBuiltinComparable(self: *Resolver, a: global_sg.GlobalTypeId, b: global_sg.GlobalTypeId) bool {
        if (!types.equal(self.graph, a, b)) return false;
        return switch (types.representation(self.graph, a) orelse return false) {
            .builtin => |value| value != .Void and value != .Type and value != .Any,
            else => false,
        };
    }

    pub fn isTagOrForeignEqualityRepresentation(self: *const Resolver, left: global_sg.GlobalTypeId, right: global_sg.GlobalTypeId) bool {
        if (!types.equal(self.graph, left, right)) return false;
        if (self.isCEnumPair(left, right) or c_abi.isFunctionPointer(self.graph, left)) return true;
        const variants = types.variants(self.graph, left) orelse return false;
        for (self.graph.variants.items[variants.start..][0..variants.len]) |variant|
            if (variant.payload_type != null) return false;
        return true;
    }

    fn isCEnumPair(self: *const Resolver, a: global_sg.GlobalTypeId, b: global_sg.GlobalTypeId) bool {
        if (!types.equal(self.graph, a, b)) return false;
        return switch (self.graph.resolvedSemanticType(a) orelse return false) {
            .nominal => |decl| self.graph.typeDefinition(decl).choice_layout == .c_enum,
            else => false,
        };
    }

    /// Resolve a source qualifier through the module aliases linked before
    /// semantic resolution. Paths are no longer semantic identity here.
    pub fn findModuleForQualifier(self: *Resolver, current_module: usize, spelling: []const u8) !global_sg.GlobalModuleId {
        const symbolic = std.mem.startsWith(u8, spelling, "@alias:");
        const qualifier = if (symbolic) spelling["@alias:".len..] else spelling;
        var found: ?global_sg.GlobalModuleId = null;
        const current: global_sg.GlobalModuleId = @enumFromInt(@as(u32, @intCast(current_module)));
        for (self.graph.module_aliases.items) |alias| {
            // Interactive submissions share aliases only with later members of
            // their explicit namespace. Dependencies retain lexical imports.
            if (!self.graph.sameModuleNamespace(alias.owner, current) and
                (@intFromEnum(alias.owner) > current_module or !self.sameDeclarationNamespace(@intFromEnum(alias.owner), current_module))) continue;
            const declaration = self.graph.declarations.items[@intFromEnum(alias.declaration)];
            const name = self.graph.text(declaration.name);
            var target = alias.target;
            if (!std.mem.eql(u8, name, qualifier)) {
                if (!symbolic) continue;
                if (qualifier.len <= name.len or !std.mem.startsWith(u8, qualifier, name) or qualifier[name.len] != '/') continue;
                const dir = self.graph.text(self.graph.modules.items[@intFromEnum(alias.target)].dir);
                const path = try std.fs.path.resolve(self.allocator, &.{ dir, qualifier[name.len + 1 ..] });
                defer self.allocator.free(path);
                var child: ?global_sg.GlobalModuleId = null;
                for (self.graph.modules.items, 0..) |candidate, index| {
                    if (std.mem.eql(u8, self.graph.text(candidate.dir), path)) child = @enumFromInt(@as(u32, @intCast(index)));
                }
                target = child orelse return error.UnknownModuleReference;
            }
            if (found) |previous| {
                if (previous != target) return error.AmbiguousModuleReference;
            } else found = target;
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

    pub fn appendNode(self: *Resolver, source: primitives.SourceRef, ty: global_sg.GlobalTypeId, content: global_sg.Node.Content) !global_sg.GlobalNodeId {
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
    try std.testing.expectEqual(Resolver.RecordMatch.deferred, resolver.matchCallInput(expected, @enumFromInt(1)));
    graph.nodes.items[0].ty = bool_ty;
    try std.testing.expectEqual(Resolver.RecordMatch.no_match, resolver.matchCallInput(expected, @enumFromInt(1)));
    graph.nodes.items[0].ty = int_ty;
    const matched = resolver.matchCallInput(expected, @enumFromInt(1));
    try std.testing.expectEqual(Resolver.RecordMatch.applicable, matched);
}
test "record literals and call arguments reject unknown fields even when defaults cover every field" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    const int: global_sg.GlobalTypeId = @enumFromInt(0);
    const record: global_sg.GlobalTypeId = @enumFromInt(1);
    const left = try graph.addString(allocator, "left");
    const right = try graph.addString(allocator, "right");
    const unknown = try graph.addString(allocator, "unknown");
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.nodes.append(allocator, .{ .source = source, .ty = int, .content = .{ .int_literal = 42 } });
    try graph.fields.appendSlice(allocator, &.{
        .{ .name = left, .ty = int, .source = source, .default_value = @enumFromInt(0) },
        .{ .name = right, .ty = int, .source = source, .default_value = @enumFromInt(0) },
    });
    const fields = global_sg.FieldRange{ .start = 0, .len = 2 };
    try graph.types.append(allocator, .{ .structural = .{ .fields = fields } });
    try graph.value_fields.append(allocator, .{ .name = unknown, .value = @enumFromInt(0) });
    const literal: global_sg.GlobalNodeId = @enumFromInt(1);
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 1 } } } });
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    try std.testing.expectEqual(Resolver.RecordMatch.no_match, resolver.matchCallInput(fields, literal));
    try std.testing.expect(!resolver.contextualLiteralFits(literal, record));
    try std.testing.expect(!try resolver.completeRecordValue(record, literal, reach_context.Context.fromGlobal(&.{}, null)));
    graph.value_fields.items[0].name = left;
    try std.testing.expectEqual(Resolver.RecordMatch.applicable, resolver.matchCallInput(fields, literal));
    try std.testing.expect(resolver.contextualLiteralFits(literal, record));
    try std.testing.expect(try resolver.completeRecordValue(record, literal, reach_context.Context.fromGlobal(&.{}, null)));
    try std.testing.expect(types.equal(&graph, graph.node(literal).ty.?, record));
    try std.testing.expectEqual(@as(u32, 2), graph.node(literal).content.struct_value_literal.fields.len);
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
    try std.testing.expect(try resolver.materializeAssignmentValues());
    try std.testing.expectEqual(aggregate_ty, graph.nodes.items[1].ty.?);
    try std.testing.expectEqual(int_ty, graph.nodes.items[0].ty.?);
    try std.testing.expect(!try resolver.materializeAssignmentValues());
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
    try resolver.coerceIntegerPair(@enumFromInt(0), &left, @enumFromInt(1), &right);
    try std.testing.expectEqual(@as(global_sg.GlobalTypeId, @enumFromInt(0)), left);
    try std.testing.expectEqual(left, right);
    graph.nodes.items[1].ty = @enumFromInt(1);
    right = @enumFromInt(1);
    try resolver.coerceIntegerPair(@enumFromInt(1), &right, @enumFromInt(0), &left);
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
    try std.testing.expect(try resolver.materializeAssignmentValues());
    try std.testing.expectEqual(@as(global_sg.GlobalTypeId, @enumFromInt(1)), graph.node(@enumFromInt(0)).ty.?);
    try std.testing.expect(!try resolver.materializeAssignmentValues());
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

    try graph.resolveType(allocator, unresolved_ty, .{ .builtin = .Int32 });
    try std.testing.expect(try resolver.materializeAddresses());
    const result_pointer = switch (graph.semanticType(graph.node(@enumFromInt(1)).ty.?)) {
        .pointer => |pointer| pointer,
        else => return error.ExpectedPointerType,
    };
    try std.testing.expectEqual(unresolved_ty, result_pointer.child);
    try std.testing.expectEqual(primitives.PointerMutability.read_only, result_pointer.mutability);
}

test "global core resolver is graph-only" {
    // Interactive visibility contributes one optional pointer, never embedded
    // namespace tables or syntax ownership in the ordinary resolver.
    try std.testing.expect(@sizeOf(Resolver) <= 200);
}

test "qualified lookup follows linked module alias" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "/workspace/app") };
    defer module.deinit(allocator);

    const app_dir = try graph.addString(allocator, "/workspace/app");
    const target_dir = try graph.addString(allocator, "/tool/more/test_support/basic");
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

test "reached signature rollback restores interfaces before discarded pools are reused" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const name = try graph.addString(allocator, "caller");
    try graph.declarations.append(allocator, .{ .kind = .function, .name = name, .source = .{ .file_index = 0, .offset = 0 } });
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.functions.append(allocator, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } });
    try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = @enumFromInt(0), .content = .{ .int_literal = 7 } });
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer resolver.deinitReachedCalls();
    const saved = graph.checkpoint();
    for ([_][]const u8{ "writer", "error_tracer" }) |field_name| {
        _ = (try resolver.propagateReachedDefault(@enumFromInt(0), .{
            .name = try graph.addString(allocator, field_name),
            .ty = @enumFromInt(0),
            .source = .{ .file_index = 0, .offset = 0 },
        }, @enumFromInt(0))).?;
    }
    try std.testing.expectEqual(@as(u32, 2), graph.functions.items[0].input_bindings.len);
    graph.rollback(allocator, saved);
    try std.testing.expectEqual(@as(u32, 0), graph.functions.items[0].input.len);
    try std.testing.expectEqual(@as(u32, 0), graph.functions.items[0].input_bindings.len);
    try std.testing.expectEqual(@as(usize, 0), graph.binding_refs.items.len);
}

test "string literal type lookup respects incomplete indexes and unresolved core types" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    const name = try graph.addString(allocator, "StringView");
    try graph.types.appendNTimes(allocator, .{ .builtin = .Int32 }, 3);
    try graph.markTypeUnresolved(allocator, @enumFromInt(1));
    for (0..2) |raw|
        try graph.declarations.append(allocator, .{ .name = name, .source = source, .kind = .type, .type_id = @enumFromInt(raw) });
    try graph.modules.append(allocator, .{ .dir = name, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 1 } });
    try graph.modules.append(allocator, .{ .dir = name, .is_bundled_core = true, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 1, .len = 1 } });
    const resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    try std.testing.expectEqual(null, resolver.defaultStringLiteralType());
    _ = try graph.declarationsNamed(allocator, "StringView");
    try std.testing.expectEqual(null, resolver.defaultStringLiteralType());
    try graph.declarations.append(allocator, .{ .name = name, .source = source, .kind = .type, .type_id = @enumFromInt(2) });
    graph.modules.items[1].declarations.len = 2;
    try std.testing.expectEqual(@as(?global_sg.GlobalTypeId, @enumFromInt(2)), resolver.defaultStringLiteralType());
    _ = try graph.declarationsNamed(allocator, "StringView");
    try std.testing.expectEqual(@as(?global_sg.GlobalTypeId, @enumFromInt(2)), resolver.defaultStringLiteralType());
    try graph.resolveType(allocator, @enumFromInt(1), .{ .builtin = .Int32 });
    try std.testing.expectEqual(@as(?global_sg.GlobalTypeId, @enumFromInt(1)), resolver.defaultStringLiteralType());
}

test "binding materialization follows pending states as bindings are appended" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    const name = try graph.addString(allocator, "value");
    try graph.types.appendSlice(allocator, &.{ .{ .builtin = .Int32 }, .{ .builtin = .Bool } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = @enumFromInt(1), .content = .{ .bool_literal = true } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .int_literal = 1 } });
    try graph.bindings.append(allocator, .{ .name = name, .source = source, .ty = @enumFromInt(0), .initialization = @enumFromInt(0), .mutability = .constant });
    try graph.bindings.append(allocator, .{ .name = name, .source = source, .ty = @enumFromInt(0), .mutability = .constant });
    try graph.bindings.append(allocator, .{ .name = name, .source = source, .ty = @enumFromInt(0), .initialization = @enumFromInt(1), .mutability = .constant });
    try graph.markBindingTypeUnresolved(allocator, @enumFromInt(1));
    try graph.markBindingTypeUnresolved(allocator, @enumFromInt(2));
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    try std.testing.expect(!try resolver.materializeBindingTypes());
    graph.nodes.items[1].ty = @enumFromInt(0);
    try std.testing.expect(try resolver.materializeBindingTypes());
    try std.testing.expect(graph.isBindingTypeUnresolved(@enumFromInt(1)));
    try std.testing.expect(!graph.isBindingTypeUnresolved(@enumFromInt(2)));
    try graph.resolveBindingType(allocator, @enumFromInt(1), @enumFromInt(1));
    try std.testing.expect(!try resolver.materializeBindingTypes());
    try graph.bindings.append(allocator, .{ .name = name, .source = source, .ty = @enumFromInt(0), .initialization = @enumFromInt(0), .mutability = .constant });
    try graph.markBindingTypeUnresolved(allocator, @enumFromInt(3));
    try std.testing.expect(try resolver.materializeBindingTypes());
    try std.testing.expectEqual(@as(global_sg.GlobalTypeId, @enumFromInt(1)), graph.bindings.items[3].ty);
    try std.testing.expectEqual(@as(global_sg.GlobalTypeId, @enumFromInt(0)), graph.bindings.items[0].ty);
}

test "completed call defaults remain reversible after nested publication" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(a: std.mem.Allocator) !void {
            var graph: global_sg.GlobalSemanticGraph = .{};
            defer graph.deinit(a);
            const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
            try graph.types.append(a, .{ .builtin = .Int32 });
            try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 42 } });
            const original: global_sg.Node = .{ .source = source, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } } };
            try graph.nodes.append(a, original);
            try graph.fields.append(a, .{ .name = try graph.addString(a, "value"), .source = source, .ty = @enumFromInt(0), .default_value = @enumFromInt(0) });
            var resolver: Resolver = .{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
            defer resolver.deinit();
            const saved = graph.checkpoint();
            var outer = graph.beginTransaction(a);
            defer outer.deinit();
            errdefer {
                outer.rollback();
                std.debug.assert(std.meta.eql(original, graph.node(@enumFromInt(1))));
                std.debug.assert(std.meta.eql(saved, graph.checkpoint()));
            }
            try std.testing.expect(try resolver.completeRecordFields(.{ .start = 0, .len = 1 }, @enumFromInt(1)));
            const completed = graph.node(@enumFromInt(1));
            try std.testing.expect(completed.ty != null);
            try std.testing.expectEqual(@as(u32, 1), completed.content.struct_value_literal.fields.len);
            try std.testing.expectEqual(@as(global_sg.GlobalNodeId, @enumFromInt(0)), graph.value_fields.items[completed.content.struct_value_literal.fields.start].value);
            outer.rollback();
            try std.testing.expectEqualDeep(original, graph.node(@enumFromInt(1)));
            try std.testing.expectEqualDeep(saved, graph.checkpoint());
        }
    }.run, .{});
}

test "contextual literal normalization rolls back every changed node on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(a: std.mem.Allocator) !void {
            var graph: global_sg.GlobalSemanticGraph = .{};
            defer graph.deinit(a);
            const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
            try graph.types.append(a, .{ .builtin = .UInt8 });
            try graph.types.append(a, .{ .array = .{ .element = @enumFromInt(0), .length = 1 } });
            const scalar: global_sg.Node = .{ .source = source, .ty = null, .content = .{ .int_literal = 42 } };
            const aggregate: global_sg.Node = .{ .source = source, .ty = null, .content = .{ .list_literal = .{ .elements = .{ .start = 0, .len = 1 } } } };
            try graph.nodes.appendSlice(a, &.{ scalar, aggregate });
            try graph.node_refs.append(a, @enumFromInt(0));
            var resolver: Resolver = .{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
            defer resolver.deinit();
            const saved = graph.checkpoint();
            var transaction = graph.beginTransaction(a);
            defer transaction.deinit();
            errdefer {
                transaction.rollback();
                std.debug.assert(std.meta.eql(saved, graph.checkpoint()));
                std.debug.assert(std.meta.eql(scalar, graph.node(@enumFromInt(0))));
                std.debug.assert(std.meta.eql(aggregate, graph.node(@enumFromInt(1))));
            }
            try std.testing.expect(try resolver.coerceContextualValue(@enumFromInt(1), @enumFromInt(1)));
            try std.testing.expectEqual(@as(global_sg.GlobalTypeId, @enumFromInt(0)), graph.node(@enumFromInt(0)).ty.?);
            try std.testing.expect(graph.node(@enumFromInt(1)).content == .array_literal);
            transaction.rollback();
            try std.testing.expectEqualDeep(scalar, graph.node(@enumFromInt(0)));
            try std.testing.expectEqualDeep(aggregate, graph.node(@enumFromInt(1)));
            try std.testing.expectEqualDeep(saved, graph.checkpoint());
        }
    }.run, .{});
}

test "arithmetic type propagation rechecks contextualized operands and preserves node order" {
    const a = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    const int: global_sg.GlobalTypeId = @enumFromInt(0);
    const byte: global_sg.GlobalTypeId = @enumFromInt(1);
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Int32 }, .{ .builtin = .UInt8 } });
    try graph.nodes.appendSlice(a, &.{
        .{ .source = source, .ty = int, .content = .{ .int_literal = 1 } },
        .{ .source = source, .ty = int, .content = .{ .int_literal = 2 } },
        .{ .source = source, .ty = int, .content = .{ .binary_operation = .{ .operator = .addition, .left = @enumFromInt(0), .right = @enumFromInt(1) } } },
        .{ .source = source, .ty = int, .content = .{ .move_value = @enumFromInt(2) } },
    });
    var core: Resolver = .{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinit();
    try std.testing.expect(!try core.materializeBindingTypes());
    // A later context retypes one literal. The old binary result type does
    // not authorize retiring this expression from subsequent sweeps.
    try graph.setNodeType(a, @enumFromInt(0), byte);
    try std.testing.expect(try core.materializeBindingTypes());
    for (graph.nodes.items) |node| try std.testing.expectEqual(@as(?global_sg.GlobalTypeId, byte), node.ty);
    try std.testing.expect(!try core.materializeBindingTypes());

    // Failure inside a semantic transaction restores all propagated types.
    var transaction = graph.beginTransaction(a);
    defer transaction.deinit();
    try graph.setNodeType(a, @enumFromInt(0), int);
    try graph.setNodeType(a, @enumFromInt(1), int);
    try std.testing.expect(try core.materializeBindingTypes());
    transaction.rollback();
    for (graph.nodes.items) |node| try std.testing.expectEqual(@as(?global_sg.GlobalTypeId, byte), node.ty);
}

test "definition lookup filters requested kinds before resolving ambiguity" {
    const a = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "app") };
    defer module.deinit(a);
    try module.strings.appendSlice(a, "operation");
    const local_name = primitives.StringRange{ .start = 0, .len = 9 };
    const name = try graph.addString(a, "operation");
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    for (0..2) |_| try graph.declarations.append(a, .{ .kind = .function, .name = name, .source = source });
    try graph.modules.append(a, .{ .dir = try graph.addString(a, "app"), .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 2 } });
    var resolver: Resolver = .{ .allocator = a, .graph = &graph, .modules = &.{module}, .offsets = &.{} };
    const reference: module_entities.ExternalRef = .{ .kind = .type, .module_path = null, .name = local_name, .source = source };
    try std.testing.expectEqual(@as(?global_sg.GlobalFamilyDefinitionId, null), try resolver.resolveDefinitionReference(0, reference, &.{.type}));
    try std.testing.expectError(error.AmbiguousGlobalDeclaration, resolver.resolveDefinitionReference(0, reference, &.{.function}));
}
