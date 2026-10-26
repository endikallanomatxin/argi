const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const dispatch_mod = @import("dispatch.zig");
const reach_context = @import("reach_context.zig");
const global_types = @import("types.zig");
const standard_contracts = @import("standard_contracts.zig");
const primitives = @import("../primitives/schema.zig");
const cleanup_activation = @import("../safety/cleanup_activation.zig");
const lexical_storage = @import("lexical_storage.zig");

pub const Stats = struct {
    copies: u32 = 0,
    deinit_checks: u32 = 0,
    auto_deinits: u32 = 0,
    defers: u32 = 0,
    cleanup_edges: u32 = 0,
    destructor_successes: u32 = 0,
    destructor_failures: u32 = 0,
};

const Deferred = struct { marker: global_sg.GlobalNodeId, value: global_sg.GlobalNodeId };
pub const DeniedCopy = struct { source: primitives.SourceRef, ty: global_sg.GlobalTypeId };
const AutoNode = struct { binding: global_sg.GlobalBindingId, node: ?global_sg.GlobalNodeId };
const ResolvedDestructor = struct {
    function: global_sg.GlobalFunctionId,
    input: global_sg.GlobalNodeId,
    self_field_index: u32,
};

pub const Resolver = struct {
    const LoopCleanup = struct { active: usize, defers: usize };
    pub const ParameterizedCheckpoint = struct {
        deferred: usize,
        defers: u32,
        auto_nodes: usize,
        replacements: usize,
        empty_block: ?global_sg.GlobalBlockId,
    };

    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    dispatch: ?*dispatch_mod.Resolver = null,
    deferred: std.ArrayList(Deferred) = .empty,
    denied_copy: ?DeniedCopy = null,
    auto_nodes: std.ArrayList(AutoNode) = .empty,
    replacement_candidates: std.AutoHashMapUnmanaged(global_sg.GlobalNodeId, void) = .empty,
    replacement_rewrites: std.ArrayList(global_sg.GlobalNodeId) = .empty,

    empty_block: ?global_sg.GlobalBlockId = null,
    // Only the designated command's direct declarations have session duration.
    // Nested blocks and initializer temporaries retain ordinary lexical cleanup.
    continuation_function: ?global_sg.GlobalFunctionId = null,
    // Earlier session storage is visible to checked replacement planning, but
    // must not enter this command's lexical cleanup list.
    continuation_bindings: std.ArrayList(global_sg.GlobalBindingId) = .empty,
    stats: Stats = .{},
    profile_io: ?std.Io = null,
    profile_destructor_calls: usize = 0,
    profile_destructor_ns: i96 = 0,

    fn profileNow(self: *const Resolver) i96 {
        if (self.profile_io) |io| return std.Io.Timestamp.now(io, .boot).nanoseconds;
        return 0;
    }

    pub fn deinit(self: *Resolver) void {
        self.deferred.deinit(self.allocator);
        self.auto_nodes.deinit(self.allocator);
        self.continuation_bindings.deinit(self.allocator);
        self.replacement_candidates.deinit(self.allocator);
        self.replacement_rewrites.deinit(self.allocator);
    }

    pub fn tryResolve(
        self: *Resolver,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        return switch (operation) {
            .resolve_defer => |value| resolution.Result.fromBool(try self.resolveDefer(o, value)),
            .resolve_copy => |value| resolution.Result.fromBool(try self.resolveCopy(o, value)),
            .resolve_deinit => |value| resolution.Result.fromBool(try self.resolveExplicitDeinit(o, value)),
            else => .not_applicable,
        };
    }

    pub fn finalize(self: *Resolver) !void {
        const count = self.graph.functions.items.len;
        for (0..count) |raw| {
            const function = self.graph.functions.items[raw];
            if (function.body == null) continue;
            const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            _ = try self.finalizeFunctionBody(id);
        }
    }

    pub fn finalizeFunctionBody(self: *Resolver, function_id: global_sg.GlobalFunctionId) !bool {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        const body = function.body orelse return true;
        try self.materializeOutputInitializers(function, body);
        if (!self.functionReadyForCleanup(function, body)) return false;
        if (function.safety_primitive == .trusted_opaque_drop) {
            try self.materializeOpaqueDrop(function_id, function, body);
        }
        // Determine possible replacement before adding cleanup sequences. In
        // particular, an unaddressed output's first initialization has no old
        // owner and must not instantiate a destructor solely to skip it later.
        var activation_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer activation_arena.deinit();
        var activation = try cleanup_activation.collect(activation_arena.allocator(), self.graph, function_id);
        defer activation.deinit();
        var replacements = activation.replacements.keyIterator();
        while (replacements.next()) |node| try self.markReplacement(node.*);
        var visible: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer visible.deinit(self.allocator);
        if (self.continuation_function == function_id)
            try visible.appendSlice(self.allocator, self.continuation_bindings.items);
        try visible.appendSlice(
            self.allocator,
            self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len],
        );
        try visible.appendSlice(
            self.allocator,
            self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len],
        );

        var active: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer active.deinit(self.allocator);
        var defers: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer defers.deinit(self.allocator);
        const module = self.graph.moduleForDeclaration(function.declaration) orelse return error.MissingFunctionModule;
        try self.finalizeBlock(body, &active, &defers, &visible, &.{}, function_id, @intCast(@intFromEnum(module)), null);
        return true;
    }

    // The trusted boundary changes the caller's ownership facts, but destruction
    // itself uses the same selected plan as lexical and replacement cleanup.
    fn materializeOpaqueDrop(self: *Resolver, function_id: global_sg.GlobalFunctionId, function: global_sg.Function, body: global_sg.GlobalBlockId) !void {
        if (self.graph.blocks.items[@intFromEnum(body)].nodes.len != 0) return;
        if (function.input_bindings.len != 1) return error.InvalidCleanupTarget;
        const binding = self.graph.binding_refs.items[function.input_bindings.start];
        const record = self.graph.binding(binding);
        const pointer = switch (self.graph.semanticType(record.ty)) {
            .pointer => |value| value,
            else => return error.InvalidCleanupTarget,
        };
        const address = try self.appendNode(record.source, record.ty, .{ .binding_use = binding });
        const target = try self.appendNode(record.source, pointer.child, .{ .dereference = .{ .pointer = address, .ty = pointer.child, .pointer_type = record.ty } });
        const visible = try self.allocator.dupe(global_sg.GlobalBindingId, self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]);
        defer self.allocator.free(visible);
        const module = self.graph.moduleForDeclaration(function.declaration) orelse return error.MissingFunctionModule;
        var plan = try self.buildAutoDeinit(.{ .indirect = target }, target, pointer.child, reach_context.Context.fromGlobal(visible, function_id), @intFromEnum(module)) orelse return;
        plan.allow_untracked_complete = true;
        const id: global_sg.GlobalAutoDeinitId = @enumFromInt(self.graph.auto_deinits.items.len);
        try self.graph.auto_deinits.append(self.allocator, plan);
        const cleanup = try self.appendNode(record.source, try self.builtin(.Void), .{ .auto_deinit_binding = id });
        const start: u32 = @intCast(self.graph.node_refs.items.len);
        try self.graph.node_refs.append(self.allocator, cleanup);
        var updated = self.graph.blocks.items[@intFromEnum(body)];
        updated.nodes = .{ .start = start, .len = 1 };
        try self.graph.setBlock(self.allocator, body, updated);
    }

    // Output defaults execute in declaration order before source statements.
    // Represent them as ordinary first writes, so lifetime effects, once calls,
    // summaries and cleanup all consume the same ordered graph. Backends must
    // not perform another implicit initialization before these writes.
    fn materializeOutputInitializers(self: *Resolver, function: global_sg.Function, body_id: global_sg.GlobalBlockId) !void {
        const bindings = self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len];
        var defaults: u32 = 0;
        for (bindings) |binding| if (self.graph.binding(binding).initialization != null) {
            defaults += 1;
        };
        if (defaults == 0) return;
        const body = self.graph.blocks.items[@intFromEnum(body_id)];
        const start = std.math.cast(u32, self.graph.node_refs.items.len) orelse return error.SemanticGraphTooLarge;
        const count = std.math.add(u32, defaults, body.nodes.len) catch return error.SemanticGraphTooLarge;
        _ = std.math.add(u32, start, count) catch return error.SemanticGraphTooLarge;
        try self.graph.node_refs.ensureUnusedCapacity(self.allocator, count);
        for (bindings) |binding| {
            const record = self.graph.binding(binding);
            const value = record.initialization orelse continue;
            const write = try self.appendNode(record.source, null, .{ .assignment = .{ .binding = binding, .value = value } });
            self.graph.node_refs.appendAssumeCapacity(write);
        }
        self.graph.node_refs.appendSliceAssumeCapacity(self.graph.node_refs.items[body.nodes.start..][0..body.nodes.len]);
        {
            var updated = self.graph.blocks.items[@intFromEnum(body_id)];
            updated.nodes = .{ .start = start, .len = count };
            try self.graph.setBlock(self.allocator, body_id, updated);
        }
        for (bindings) |binding| {
            var updated = self.graph.bindings.items[@intFromEnum(binding)];
            updated.initialization = null;
            try self.graph.setBinding(self.allocator, binding, updated);
        }
    }

    fn functionReadyForCleanup(
        self: *const Resolver,
        function: global_sg.Function,
        body: global_sg.GlobalBlockId,
    ) bool {
        for (self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]) |binding|
            if (self.graph.isBindingTypeUnresolved(binding)) return false;
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |binding|
            if (self.graph.isBindingTypeUnresolved(binding)) return false;
        return self.blockReadyForCleanup(body);
    }

    fn blockReadyForCleanup(self: *const Resolver, block_id: global_sg.GlobalBlockId) bool {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            // Deferred markers hide executable bodies; their local binding
            // types must resolve before cleanup can be finalized once.
            const effective_node = self.deferValue(node_id) orelse node_id;
            const node = self.graph.nodes.items[@intFromEnum(effective_node)];
            switch (node.content) {
                .binding_declaration => |binding| if (self.graph.isBindingTypeUnresolved(binding)) return false,
                .binding_use => |binding| if (self.graph.isBindingTypeUnresolved(binding)) return false,
                .assignment => |assignment| if (self.graph.isBindingTypeUnresolved(assignment.binding)) return false,
                .code_block, .value_sequence, .replacement => |child| if (!self.blockReadyForCleanup(child)) return false,
                .if_statement => |statement| {
                    if (!self.blockReadyForCleanup(statement.then_block)) return false;
                    if (statement.else_block) |child|
                        if (!self.blockReadyForCleanup(child)) return false;
                },
                .while_statement => |statement| if (!self.blockReadyForCleanup(statement.body)) return false,
                .for_statement => |statement| {
                    if (statement.init) |init| {
                        const init_node = self.graph.nodes.items[@intFromEnum(init)];
                        if (init_node.content == .code_block or init_node.content == .value_sequence or init_node.content == .replacement) {
                            const initialization_block = switch (init_node.content) {
                                .value_sequence, .replacement, .code_block => |child| child,
                                else => unreachable,
                            };
                            if (!self.blockReadyForCleanup(initialization_block)) return false;
                        }
                    }
                    if (!self.blockReadyForCleanup(statement.body)) return false;
                },
                .switch_statement => |switch_id| {
                    const sw = self.graph.switches.items[@intFromEnum(switch_id)];
                    for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case| {
                        if (case.payload_binding) |binding|
                            if (self.graph.isBindingTypeUnresolved(binding)) return false;
                        if (!self.blockReadyForCleanup(case.body)) return false;
                    }
                    if (sw.default_block) |child|
                        if (!self.blockReadyForCleanup(child)) return false;
                },
                else => {},
            }
        }
        return true;
    }

    fn resolveDefer(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const marker = globalizer.globalNode(o, value.node);
        const deferred_value = globalizer.globalNode(o, value.value);
        try self.registerDefer(marker, deferred_value);
        return true;
    }

    pub fn registerParameterizedDefer(context: *anyopaque, marker: global_sg.GlobalNodeId, deferred_value: global_sg.GlobalNodeId) anyerror!void {
        const self: *Resolver = @ptrCast(@alignCast(context));
        try self.registerDefer(marker, deferred_value);
    }

    pub fn parameterizedCheckpoint(context: *anyopaque) ParameterizedCheckpoint {
        const self: *Resolver = @ptrCast(@alignCast(context));
        return .{ .deferred = self.deferred.items.len, .defers = self.stats.defers, .auto_nodes = self.auto_nodes.items.len, .replacements = self.replacement_rewrites.items.len, .empty_block = self.empty_block };
    }

    pub fn rollbackParameterizedCheckpoint(context: *anyopaque, saved: ParameterizedCheckpoint) void {
        const self: *Resolver = @ptrCast(@alignCast(context));
        self.deferred.shrinkRetainingCapacity(saved.deferred);
        self.auto_nodes.shrinkRetainingCapacity(saved.auto_nodes);
        while (self.replacement_rewrites.items.len > saved.replacements)
            std.debug.assert(self.replacement_candidates.remove(self.replacement_rewrites.pop().?));
        self.empty_block = saved.empty_block;
        self.stats.defers = saved.defers;
    }

    fn markReplacement(self: *Resolver, node: global_sg.GlobalNodeId) !void {
        if (self.replacement_candidates.contains(node)) return;
        try self.replacement_rewrites.ensureUnusedCapacity(self.allocator, 1);
        try self.replacement_candidates.put(self.allocator, node, {});
        self.replacement_rewrites.appendAssumeCapacity(node);
    }

    pub fn commitReplacements(self: *Resolver) void {
        self.replacement_rewrites.deinit(self.allocator);
        self.replacement_rewrites = .empty;
    }

    fn registerDefer(self: *Resolver, marker: global_sg.GlobalNodeId, deferred_value: global_sg.GlobalNodeId) !void {
        try self.deferred.append(self.allocator, .{ .marker = marker, .value = deferred_value });
        try self.makeNoop(marker, self.graph.nodes.items[@intFromEnum(deferred_value)].source);
        self.stats.defers += 1;
    }

    fn resolveCopy(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const source = globalizer.globalNode(o, value.value);
        const target = globalizer.globalNode(o, value.node);
        return self.resolveGlobalCopy(source, target);
    }

    /// Resolve implicit copying identically for lowered and inherited inputs.
    pub fn resolveGlobalCopy(self: *Resolver, source: global_sg.GlobalNodeId, target: global_sg.GlobalNodeId) !bool {
        const ty = self.graph.nodes.items[@intFromEnum(source)].ty orelse return false;
        if (self.graph.isTypeUnresolved(ty)) return false;
        // Index syntax can resolve to an operator call after lowering has
        // inserted an implicit copy. The call already produces a fresh value;
        // copying its result would require a spurious copy of owned outputs.
        if (self.graph.nodes.items[@intFromEnum(source)].content == .function_call) {
            try self.graph.setNode(self.allocator, target, self.graph.nodes.items[@intFromEnum(source)]);
            return true;
        }
        if (self.implementsNamedContract(ty, "ImplicitlyCopyable")) {
            const original = self.graph.nodes.items[@intFromEnum(source)];
            try self.graph.setNode(self.allocator, target, original);
            self.stats.copies += 1;
            return true;
        }
        // An explicit copy contract does not grant permission to insert that
        // operation implicitly. This also keeps fallible copy results visible.
        if (self.hasExplicitCopyCapability(ty) or !self.triviallyCopyable(ty)) {
            // A binding use can still carry a temporal move error that Safety
            // must diagnose before the copy permission. Other expressions may
            // be part of call/initializer matching, where failure here
            // must continue to reject the candidate.
            if (self.graph.nodes.items[@intFromEnum(source)].content != .binding_use) return false;
            const binding = self.graph.nodes.items[@intFromEnum(source)].content.binding_use;
            if (std.mem.eql(u8, self.graph.text(self.graph.bindings.items[@intFromEnum(binding)].name), "#pipe_temporary")) {
                // Stabilizing a produced value must preserve its transfer into
                // a consuming argument. Repeated consumption remains a move
                // error, while borrows still use the temporary's storage.
                try self.graph.setNode(self.allocator, target, .{
                    .source = self.graph.nodes.items[@intFromEnum(source)].source,
                    .ty = ty,
                    .content = .{ .move_value = source },
                });
                return true;
            }
            if (self.denied_copy == null) self.denied_copy = .{
                .source = self.graph.nodes.items[@intFromEnum(source)].source,
                .ty = ty,
            };
            try self.graph.setNode(self.allocator, target, .{
                .source = self.graph.nodes.items[@intFromEnum(source)].source,
                .ty = ty,
                .content = .{ .denied_implicit_copy = source },
            });
            return true;
        }
        try self.graph.setNode(self.allocator, target, self.graph.nodes.items[@intFromEnum(source)]);
        self.stats.copies += 1;
        return true;
    }

    /// Whether the language may duplicate a value without an explicit `copy`
    /// operation. Match value payloads use this permission even though they do
    /// not pass through a lowered `resolve_copy` node.
    pub fn canImplicitlyCopy(self: *Resolver, ty: global_sg.GlobalTypeId) bool {
        if (self.implementsNamedContract(ty, "ImplicitlyCopyable")) return true;
        if (self.hasExplicitCopyCapability(ty)) return false;
        return self.triviallyCopyable(ty);
    }

    fn hasExplicitCopyCapability(self: *Resolver, ty: global_sg.GlobalTypeId) bool {
        if (self.implementsNamedContract(ty, "InfalliblyCopyable")) return true;
        const dispatch = self.dispatch orelse return false;
        return dispatch.contracts.mayImplementFirstParticipant("FalliblyCopyable", ty) catch true;
    }

    fn implementsNamedContract(self: *Resolver, concrete: global_sg.GlobalTypeId, name: []const u8) bool {
        const dispatch = self.dispatch orelse return false;
        const declarations = self.graph.declarationsNamed(self.allocator, name) catch return false;
        for (declarations) |contract_decl| {
            if (self.graph.declaration(contract_decl).kind != .contract_type) continue;
            if (dispatch.contracts.implements(concrete, contract_decl) catch false) return true;
        }
        return false;
    }

    fn resolveExplicitDeinit(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const binding = globalizer.globalBinding(o, value.binding);
        _ = self.autoDeinitNode(binding);
        self.stats.deinit_checks += 1;
        return true;
    }

    // Default expressions are inserted after syntax lowering. Reserve their
    // addressable storage in the same lexical block as explicit temporaries,
    // while leaving initialization at the actual argument evaluation point.
    fn collectDefaultTemporaries(self: *Resolver, id: global_sg.GlobalNodeId, output: *std.ArrayList(global_sg.GlobalNodeId)) anyerror!void {
        if (self.graph.argument_default_temporaries.items.len == 0) return;
        for (self.graph.argument_default_temporaries.items) |temporary| {
            const content = self.graph.node(id).content;
            const binding = self.graph.node(temporary.declaration).content.binding_declaration;
            if (temporary.expression != id and
                !(content == .assignment and content.assignment.binding == binding)) continue;
            if (std.mem.indexOfScalar(global_sg.GlobalNodeId, output.items, temporary.declaration) == null)
                try output.append(self.allocator, temporary.declaration);
        }
        const content = self.graph.node(id).content;
        switch (content) {
            .code_block, .value_sequence, .replacement => {}, // Their own blocks retain lexical scope.
            .struct_value_literal => |literal| {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    try self.collectDefaultTemporaries(field.value, output);
            },
            inline .list_literal, .array_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |child|
                    try self.collectDefaultTemporaries(child, output);
            },
            .binding_declaration => |binding| {
                const record = self.graph.binding(binding);
                if (!record.deferred_initialization) if (record.initialization) |value|
                    try self.collectDefaultTemporaries(value, output);
            },
            .switch_statement => |index| try self.collectDefaultTemporaries(self.graph.switches.items[@intFromEnum(index)].expression, output),
            .error_propagation => |index| try self.collectDefaultTemporaries(self.graph.error_propagations.items[@intFromEnum(index)].errable_value, output),
            .error_context => |index| {
                const value = self.graph.error_contexts.items[@intFromEnum(index)];
                try self.collectDefaultTemporaries(value.errable_value, output);
                try self.collectDefaultTemporaries(value.context, output);
            },
            .nullable_unwrap_or => |index| {
                const value = self.graph.nullable_unwraps.items[@intFromEnum(index)];
                try self.collectDefaultTemporaries(value.nullable_value, output);
                try self.collectDefaultTemporaries(value.fallback_value, output);
            },
            .testing_expect_error => |index| {
                const value = self.graph.testing_expect_errors.items[@intFromEnum(index)];
                try self.collectDefaultTemporaries(value.expected_reason, output);
                try self.collectDefaultTemporaries(value.actual_result, output);
                if (value.test_fail_input) |input| try self.collectDefaultTemporaries(input, output);
            },
            .virtualize => |index| try self.collectDefaultTemporaries(self.graph.virtualizes.items[@intFromEnum(index)].value, output),
            .virtual_call => |index| {
                const value = self.graph.virtual_calls.items[@intFromEnum(index)];
                try self.collectDefaultTemporaries(value.handle, output);
                try self.collectDefaultTemporaries(value.input, output);
            },
            else => try self.collectDefaultOperands(content, output),
        }
    }

    fn collectDefaultOperands(self: *Resolver, value: anytype, output: *std.ArrayList(global_sg.GlobalNodeId)) anyerror!void {
        const T = @TypeOf(value);
        if (T == global_sg.GlobalNodeId) {
            try self.collectDefaultTemporaries(value, output);
        } else switch (@typeInfo(T)) {
            .optional => if (value) |child| try self.collectDefaultOperands(child, output),
            .@"struct" => |info| inline for (info.fields) |field| try self.collectDefaultOperands(@field(value, field.name), output),
            .@"union" => switch (value) {
                inline else => |child| try self.collectDefaultOperands(child, output),
            },
            else => {},
        }
    }

    // An aggregate/call cannot take ownership of an operand until all later
    // operands have evaluated successfully. Keep evaluated operands in ordinary
    // lexical owners across possible early exits, then move them into the result.
    fn mayExitExpression(self: *const Resolver, id: global_sg.GlobalNodeId, depth: usize) bool {
        if (depth > 128) return true;
        return switch (self.graph.node(id).content) {
            .error_propagation, .error_context, .return_statement, .break_statement, .continue_statement, .testing_expect_error => true,
            .struct_value_literal => |literal| blk: {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    if (self.mayExitExpression(field.value, depth + 1)) break :blk true;
                break :blk false;
            },
            inline .list_literal, .array_literal => |literal| blk: {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |child|
                    if (self.mayExitExpression(child, depth + 1)) break :blk true;
                break :blk false;
            },
            .binding_declaration => |binding| if (self.graph.binding(binding).initialization) |value| self.mayExitExpression(value, depth + 1) else false,
            .code_block, .value_sequence, .replacement => |body| self.mayExitBlock(body, depth + 1),
            .if_statement => |value| self.mayExitExpression(value.condition, depth + 1) or self.mayExitBlock(value.then_block, depth + 1) or
                (if (value.else_block) |body| self.mayExitBlock(body, depth + 1) else false),
            .while_statement, .for_statement, .switch_statement => true,
            .virtual_call => |index| blk: {
                const call = self.graph.virtual_calls.items[@intFromEnum(index)];
                break :blk self.mayExitExpression(call.handle, depth + 1) or self.mayExitExpression(call.input, depth + 1);
            },
            .nullable_unwrap_or => |index| blk: {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(index)];
                break :blk self.mayExitExpression(unwrap.nullable_value, depth + 1) or self.mayExitExpression(unwrap.fallback_value, depth + 1);
            },
            else => |content| self.mayExitOperands(content, depth + 1),
        };
    }

    fn mayExitBlock(self: *const Resolver, id: global_sg.GlobalBlockId, depth: usize) bool {
        const block = self.graph.blocks.items[@intFromEnum(id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node|
            if (self.mayExitExpression(node, depth + 1)) return true;
        return if (block.ret_val) |value| self.mayExitExpression(value, depth + 1) else false;
    }

    fn mayExitOperands(self: *const Resolver, value: anytype, depth: usize) bool {
        const T = @TypeOf(value);
        if (T == global_sg.GlobalNodeId) return self.mayExitExpression(value, depth);
        return switch (@typeInfo(T)) {
            .optional => if (value) |child| self.mayExitOperands(child, depth) else false,
            .@"struct" => |info| blk: {
                inline for (info.fields) |field| if (self.mayExitOperands(@field(value, field.name), depth)) break :blk true;
                break :blk false;
            },
            .@"union" => switch (value) {
                inline else => |child| self.mayExitOperands(child, depth),
            },
            else => false,
        };
    }

    fn needsStagedFields(self: *const Resolver, fields: primitives.Range(global_sg.GlobalValueFieldId)) bool {
        if (fields.len < 2) return false;
        for (self.graph.value_fields.items[fields.start + 1 ..][0 .. fields.len - 1]) |field|
            if (self.mayExitExpression(field.value, 0)) return true;
        return false;
    }

    fn stageOperand(self: *Resolver, value: global_sg.GlobalNodeId, statements: *std.ArrayList(global_sg.GlobalNodeId)) !global_sg.GlobalNodeId {
        const node = self.graph.node(value);
        const ty = node.ty orelse return error.UnresolvedAggregateOperand;
        const binding: global_sg.GlobalBindingId = @enumFromInt(self.graph.bindings.items.len);
        try self.graph.bindings.append(self.allocator, .{
            .name = try self.graph.addString(self.allocator, "#evaluated_operand"),
            .source = node.source,
            .ty = ty,
            .mutability = .constant,
            .initialization = value,
        });
        try statements.append(self.allocator, try self.appendNode(node.source, null, .{ .binding_declaration = binding }));
        const use = try self.appendNode(node.source, ty, .{ .binding_use = binding });
        return self.appendNode(node.source, ty, .{ .move_value = use });
    }

    fn stageFields(self: *Resolver, range: primitives.Range(global_sg.GlobalValueFieldId), statements: *std.ArrayList(global_sg.GlobalNodeId)) !primitives.Range(global_sg.GlobalValueFieldId) {
        const fields = try self.allocator.dupe(global_sg.ValueField, self.graph.value_fields.items[range.start..][0..range.len]);
        defer self.allocator.free(fields);
        for (fields) |*field| field.value = try self.stageOperand(field.value, statements);
        const start: u32 = @intCast(self.graph.value_fields.items.len);
        try self.graph.value_fields.appendSlice(self.allocator, fields);
        return .{ .start = start, .len = range.len };
    }

    fn stageCompound(self: *Resolver, id: global_sg.GlobalNodeId) !bool {
        var node = self.graph.node(id);
        var statements: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer statements.deinit(self.allocator);
        switch (node.content) {
            .struct_value_literal => |*literal| {
                if (!self.needsStagedFields(literal.fields)) return false;
                literal.fields = try self.stageFields(literal.fields, &statements);
            },
            .function_call => |*call| {
                var input = self.graph.node(call.input);
                if (input.content != .struct_value_literal or !self.needsStagedFields(input.content.struct_value_literal.fields)) return false;
                if (call.callee_value) |value| call.callee_value = try self.stageOperand(value, &statements);
                input.content.struct_value_literal.fields = try self.stageFields(input.content.struct_value_literal.fields, &statements);
                call.input = try self.appendNode(input.source, input.ty, input.content);
            },
            .virtual_call => |index| {
                var call = self.graph.virtual_calls.items[@intFromEnum(index)];
                var input = self.graph.node(call.input);
                if (input.content != .struct_value_literal or !self.needsStagedFields(input.content.struct_value_literal.fields)) return false;
                call.handle = try self.stageOperand(call.handle, &statements);
                const range = input.content.struct_value_literal.fields;
                const fields = try self.allocator.dupe(global_sg.ValueField, self.graph.value_fields.items[range.start..][0..range.len]);
                defer self.allocator.free(fields);
                // The receiver is evaluated through handle, not again through
                // its input field. Preserve that single evaluation in the plan.
                for (fields, 0..) |*field, position|
                    field.value = if (position == call.self_input_index) call.handle else try self.stageOperand(field.value, &statements);
                const start: u32 = @intCast(self.graph.value_fields.items.len);
                try self.graph.value_fields.appendSlice(self.allocator, fields);
                input.content.struct_value_literal.fields = .{ .start = start, .len = range.len };
                call.input = try self.appendNode(input.source, input.ty, input.content);
                const staged: global_sg.GlobalVirtualCallId = @enumFromInt(self.graph.virtual_calls.items.len);
                try self.graph.virtual_calls.append(self.allocator, call);
                node.content = .{ .virtual_call = staged };
            },
            inline .list_literal, .array_literal => |*literal| {
                if (literal.elements.len < 2) return false;
                const elements = try self.allocator.dupe(global_sg.GlobalNodeId, self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]);
                defer self.allocator.free(elements);
                var needed = false;
                for (elements[1..]) |element| if (self.mayExitExpression(element, 0)) {
                    needed = true;
                    break;
                };
                if (!needed) return false;
                for (elements) |*element| element.* = try self.stageOperand(element.*, &statements);
                const start: u32 = @intCast(self.graph.node_refs.items.len);
                try self.graph.node_refs.appendSlice(self.allocator, elements);
                literal.elements = .{ .start = start, .len = @intCast(elements.len) };
            },
            else => return false,
        }
        const result = try self.appendNode(node.source, node.ty, node.content);
        try statements.append(self.allocator, result);
        const start: u32 = @intCast(self.graph.node_refs.items.len);
        try self.graph.node_refs.appendSlice(self.allocator, statements.items);
        const body: global_sg.GlobalBlockId = @enumFromInt(self.graph.blocks.items.len);
        try self.graph.blocks.append(self.allocator, .{ .nodes = .{ .start = start, .len = @intCast(statements.items.len) }, .ret_val = result });
        try self.graph.setNodeContent(self.allocator, id, .{ .value_sequence = body });
        return true;
    }

    fn finalizeExpressionCleanup(
        self: *Resolver,
        node_id: global_sg.GlobalNodeId,
        active: []const global_sg.GlobalBindingId,
        defers: []const global_sg.GlobalNodeId,
        visible: []const global_sg.GlobalBindingId,
        owner_function: global_sg.GlobalFunctionId,
        module_index: usize,
        loop_cleanup: ?LoopCleanup,
    ) anyerror!void {
        _ = try self.stageCompound(node_id);
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        switch (node.content) {
            .replacement => {}, // Already finalized when the transition was built.
            .code_block, .value_sequence => |block| {
                // Expressions may contain conditional statement effects. Give
                // their blocks the same lexical cleanup context as source
                // blocks, including early returns and branch-local owners.
                var nested_active: std.ArrayList(global_sg.GlobalBindingId) = .empty;
                defer nested_active.deinit(self.allocator);
                try nested_active.appendSlice(self.allocator, active);
                var nested_defers: std.ArrayList(global_sg.GlobalNodeId) = .empty;
                defer nested_defers.deinit(self.allocator);
                try nested_defers.appendSlice(self.allocator, defers);
                var nested_visible: std.ArrayList(global_sg.GlobalBindingId) = .empty;
                defer nested_visible.deinit(self.allocator);
                try nested_visible.appendSlice(self.allocator, visible);
                try self.finalizeBlock(block, &nested_active, &nested_defers, &nested_visible, &.{}, owner_function, module_index, loop_cleanup);
            },
            .return_statement => |ret| if (ret.expression) |value|
                try self.finalizeExpressionCleanup(value, active, defers, visible, owner_function, module_index, loop_cleanup),
            .if_statement => |statement| try self.finalizeExpressionCleanup(statement.condition, active, defers, visible, owner_function, module_index, loop_cleanup),
            .while_statement => |statement| try self.finalizeExpressionCleanup(statement.condition, active, defers, visible, owner_function, module_index, loop_cleanup),
            .switch_statement => |id| try self.finalizeExpressionCleanup(self.graph.switches.items[@intFromEnum(id)].expression, active, defers, visible, owner_function, module_index, loop_cleanup),
            .binding_declaration => |binding| {
                const record = self.graph.bindings.items[@intFromEnum(binding)];
                if (!record.deferred_initialization) if (record.initialization) |initialization|
                    try self.finalizeExpressionCleanup(initialization, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            .error_propagation => |propagation_id| {
                const propagation = self.graph.error_propagations.items[@intFromEnum(propagation_id)];
                try self.finalizeExpressionCleanup(propagation.errable_value, active, defers, visible, owner_function, module_index, loop_cleanup);
                const cleanup = try self.appendCleanup(active, defers);
                var updated = propagation;
                updated.cleanup_nodes = cleanup;
                try self.graph.setErrorPropagation(self.allocator, propagation_id, updated);
            },
            .error_context => |context_id| {
                const context = self.graph.error_contexts.items[@intFromEnum(context_id)];
                try self.finalizeExpressionCleanup(context.errable_value, active, defers, visible, owner_function, module_index, loop_cleanup);
                try self.finalizeExpressionCleanup(context.context, active, defers, visible, owner_function, module_index, loop_cleanup);
                const cleanup = try self.appendCleanup(active, defers);
                var updated = context;
                updated.cleanup_nodes = cleanup;
                try self.graph.setErrorContext(self.allocator, context_id, updated);
            },
            .move_value, .denied_implicit_copy, .address_of => |child| try self.finalizeExpressionCleanup(child, active, defers, visible, owner_function, module_index, loop_cleanup),
            .assignment => |assignment| {
                const value = try self.bindingReplacement(node_id, assignment.binding, assignment.value, visible, owner_function, module_index);
                {
                    var updated = self.graph.node(node_id);
                    updated.content.assignment.value = value;
                    try self.graph.setNode(self.allocator, node_id, updated);
                }
                try self.finalizeExpressionCleanup(value, active, defers, visible, owner_function, module_index, loop_cleanup);
                if (value != assignment.value) try self.wrapReplacement(node_id);
            },
            .function_call => |call| {
                if (call.callee_value) |value| try self.finalizeExpressionCleanup(value, active, defers, visible, owner_function, module_index, loop_cleanup);
                try self.finalizeExpressionCleanup(call.input, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            .virtualize => |virtualize_id| try self.finalizeExpressionCleanup(
                self.graph.virtualizes.items[@intFromEnum(virtualize_id)].value,
                active,
                defers,
                visible,
                owner_function,
                module_index,
                loop_cleanup,
            ),
            .virtual_call => |virtual_call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
                try self.finalizeExpressionCleanup(call.handle, active, defers, visible, owner_function, module_index, loop_cleanup);
                try self.finalizeExpressionCleanup(call.input, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            .struct_value_literal => |literal| {
                const fields = try self.allocator.dupe(global_sg.ValueField, self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]);
                defer self.allocator.free(fields);
                for (fields) |field|
                    try self.finalizeExpressionCleanup(field.value, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            .list_literal => |literal| {
                const elements = try self.allocator.dupe(global_sg.GlobalNodeId, self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]);
                defer self.allocator.free(elements);
                for (elements) |element|
                    try self.finalizeExpressionCleanup(element, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            .array_literal => |literal| {
                const elements = try self.allocator.dupe(global_sg.GlobalNodeId, self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]);
                defer self.allocator.free(elements);
                for (elements) |element|
                    try self.finalizeExpressionCleanup(element, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            .choice_literal => |literal| if (literal.payload) |payload|
                try self.finalizeExpressionCleanup(payload, active, defers, visible, owner_function, module_index, loop_cleanup),
            .struct_field_access => |access| try self.finalizeExpressionCleanup(access.value, active, defers, visible, owner_function, module_index, loop_cleanup),
            .choice_payload_access => |access| try self.finalizeExpressionCleanup(access.value, active, defers, visible, owner_function, module_index, loop_cleanup),
            .nullable_unwrap_or => |unwrap_id| {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
                try self.finalizeExpressionCleanup(unwrap.nullable_value, active, defers, visible, owner_function, module_index, loop_cleanup);
                try self.finalizeExpressionCleanup(unwrap.fallback_value, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            .array_index => |access| {
                try self.finalizeExpressionCleanup(access.array_ptr, active, defers, visible, owner_function, module_index, loop_cleanup);
                try self.finalizeExpressionCleanup(access.index, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            .array_store => |store| {
                // An indexed destination is an evaluated reference, not a
                // lexical cleanup path. Normalize it to the ordinary indirect
                // write so capture, replacement and activation share one plan.
                const source = self.graph.node(node_id).source;
                const element = try self.appendNode(source, store.element_type, .{ .array_index = .{
                    .array_ptr = store.array_ptr,
                    .index = store.index,
                    .element_type = store.element_type,
                    .array_type = store.array_type,
                } });
                const pointer = try self.appendNode(source, try self.core.pointerType(store.element_type, .read_write), .{ .address_of = element });
                const pointer_type = self.graph.node(pointer).ty.?;
                const target = try self.appendNode(source, store.element_type, .{ .dereference = .{ .pointer = pointer, .pointer_type = pointer_type, .ty = store.element_type } });
                try self.markReplacement(node_id);
                const value = try self.indirectReplacement(node_id, target, store.value, visible, owner_function, module_index);
                if (value != store.value) {
                    try self.graph.setNodeContent(self.allocator, node_id, .{ .pointer_assignment = .{ .pointer = pointer, .value = value, .cleanup_target = target } });
                    try self.finalizeExpressionCleanup(pointer, active, defers, visible, owner_function, module_index, loop_cleanup);
                    try self.finalizeExpressionCleanup(value, active, defers, visible, owner_function, module_index, loop_cleanup);
                    try self.wrapReplacement(node_id);
                } else {
                    try self.finalizeExpressionCleanup(store.array_ptr, active, defers, visible, owner_function, module_index, loop_cleanup);
                    try self.finalizeExpressionCleanup(store.index, active, defers, visible, owner_function, module_index, loop_cleanup);
                    try self.finalizeExpressionCleanup(store.value, active, defers, visible, owner_function, module_index, loop_cleanup);
                }
            },
            .struct_field_store => |store| {
                try self.finalizeExpressionCleanup(store.struct_ptr, active, defers, visible, owner_function, module_index, loop_cleanup);
                const parent = try self.lexicalAddressTarget(store.struct_ptr, visible);
                {
                    const base = parent orelse try self.appendNode(self.graph.node(node_id).source, store.struct_type, .{ .dereference = .{ .pointer = store.struct_ptr, .pointer_type = self.graph.node(store.struct_ptr).ty.?, .ty = store.struct_type } });
                    const fields = global_types.fields(self.graph, store.struct_type) orelse return error.InvalidCleanupTarget;
                    const field = self.graph.fields.items[fields.start + store.field_index];
                    const target = try self.appendNode(self.graph.node(node_id).source, store.field_type, .{ .struct_field_access = .{
                        .value = base,
                        .field_name = field.name,
                        .field_index = store.field_index,
                    } });
                    {
                        var updated = self.graph.node(node_id);
                        updated.content.struct_field_store.cleanup_target = target;
                        try self.graph.setNode(self.allocator, node_id, updated);
                    }
                    const value = if (parent != null)
                        try self.projectedReplacement(node_id, target, store.value, visible, owner_function, module_index)
                    else
                        try self.indirectReplacement(node_id, target, store.value, visible, owner_function, module_index);
                    {
                        var updated = self.graph.node(node_id);
                        updated.content.struct_field_store.value = value;
                        try self.graph.setNode(self.allocator, node_id, updated);
                    }
                    try self.finalizeExpressionCleanup(value, active, defers, visible, owner_function, module_index, loop_cleanup);
                    if (value != store.value) try self.wrapReplacement(node_id);
                }
            },
            .binary_operation => |operation| {
                try self.finalizeExpressionCleanup(operation.left, active, defers, visible, owner_function, module_index, loop_cleanup);
                try self.finalizeExpressionCleanup(operation.right, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            .comparison => |comparison| {
                try self.finalizeExpressionCleanup(comparison.left, active, defers, visible, owner_function, module_index, loop_cleanup);
                try self.finalizeExpressionCleanup(comparison.right, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            .logical_operation => |operation| {
                try self.finalizeExpressionCleanup(operation.left, active, defers, visible, owner_function, module_index, loop_cleanup);
                try self.finalizeExpressionCleanup(operation.right, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            .pointer_assignment => |assignment| {
                try self.finalizeExpressionCleanup(assignment.pointer, active, defers, visible, owner_function, module_index, loop_cleanup);
                const lexical = try self.lexicalAddressTarget(assignment.pointer, visible);
                const child = self.graph.semanticType(self.graph.node(assignment.pointer).ty.?).pointer.child;
                const target = lexical orelse try self.appendNode(self.graph.node(node_id).source, child, .{ .dereference = .{ .pointer = assignment.pointer, .pointer_type = self.graph.node(assignment.pointer).ty.?, .ty = child } });
                {
                    var updated = self.graph.node(node_id);
                    updated.content.pointer_assignment.cleanup_target = target;
                    try self.graph.setNode(self.allocator, node_id, updated);
                }
                const value = if (lexical != null)
                    try self.projectedReplacement(node_id, target, assignment.value, visible, owner_function, module_index)
                else
                    try self.indirectReplacement(node_id, target, assignment.value, visible, owner_function, module_index);
                {
                    var updated = self.graph.node(node_id);
                    updated.content.pointer_assignment.value = value;
                    try self.graph.setNode(self.allocator, node_id, updated);
                }
                try self.finalizeExpressionCleanup(value, active, defers, visible, owner_function, module_index, loop_cleanup);
                if (value != assignment.value) try self.wrapReplacement(node_id);
            },
            .explicit_cast => |cast| try self.finalizeExpressionCleanup(cast.value, active, defers, visible, owner_function, module_index, loop_cleanup),

            .testing_expect_error => |expect_id| {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(expect_id)];
                try self.finalizeExpressionCleanup(expect.expected_reason, active, defers, visible, owner_function, module_index, loop_cleanup);
                try self.finalizeExpressionCleanup(expect.actual_result, active, defers, visible, owner_function, module_index, loop_cleanup);
                if (expect.test_fail_input) |input| try self.finalizeExpressionCleanup(input, active, defers, visible, owner_function, module_index, loop_cleanup);
            },
            else => {},
        }
    }

    /// Evaluate the replacement into a lexical owner before destroying the old
    /// value. The sequence is ordinary checked graph code: destructor effects,
    /// auxiliary arguments, failure cleanup, and the final move remain visible
    /// to every consumer rather than being invented by either backend.
    fn bindingReplacement(
        self: *Resolver,
        node_id: global_sg.GlobalNodeId,
        binding: global_sg.GlobalBindingId,
        value: global_sg.GlobalNodeId,
        visible: []const global_sg.GlobalBindingId,
        owner_function: global_sg.GlobalFunctionId,
        module_index: usize,
    ) !global_sg.GlobalNodeId {
        if (!self.replacement_candidates.contains(node_id)) return value;
        try self.prepareAutoDeinit(binding, reach_context.Context.fromGlobal(visible, owner_function), module_index);
        const original_cleanup = self.autoDeinitNode(binding) orelse return value;
        // Each replacement has its own activation identity. An output's first
        // assignment cannot destroy an old value, while a later one may.
        const original_id = self.graph.node(original_cleanup).content.auto_deinit_binding;
        const plan = self.graph.auto_deinits.items[@intFromEnum(original_id)];
        const cleanup_id: global_sg.GlobalAutoDeinitId = @enumFromInt(@as(u32, @intCast(self.graph.auto_deinits.items.len)));
        try self.graph.auto_deinits.append(self.allocator, plan);
        const cleanup = try self.appendNode(self.graph.node(value).source, try self.builtin(.Void), .{ .auto_deinit_binding = cleanup_id });
        return self.replacementValue(value, self.graph.binding(binding).ty, cleanup);
    }

    fn lexicalAddressTarget(self: *Resolver, pointer: global_sg.GlobalNodeId, visible: []const global_sg.GlobalBindingId) !?global_sg.GlobalNodeId {
        const raw = lexical_storage.addressedTarget(self.graph, pointer) orelse return null;
        const target = try self.lexicalTarget(raw);
        const root = lexical_storage.root(self.graph, target) orelse return null;
        return if (std.mem.indexOfScalar(global_sg.GlobalBindingId, visible, root) != null) target else null;
    }

    // Materialize only a pure projection for cleanup metadata. The write keeps
    // its original pointer operand, preserving validity and evaluation order.
    fn lexicalTarget(self: *Resolver, target: global_sg.GlobalNodeId) anyerror!global_sg.GlobalNodeId {
        const node = self.graph.node(target);
        return switch (node.content) {
            .binding_use => target,
            .struct_field_access => |field| blk: {
                const parent = try self.lexicalTarget(field.value);
                if (parent == field.value) break :blk target;
                var projected = field;
                projected.value = parent;
                break :blk try self.appendNode(node.source, node.ty, .{ .struct_field_access = projected });
            },
            .dereference => |value| try self.lexicalTarget(lexical_storage.addressedTarget(self.graph, value.pointer) orelse return error.InvalidCleanupTarget),
            else => error.InvalidCleanupTarget,
        };
    }

    fn projectedReplacement(
        self: *Resolver,
        node_id: global_sg.GlobalNodeId,
        target: global_sg.GlobalNodeId,
        value: global_sg.GlobalNodeId,
        visible: []const global_sg.GlobalBindingId,
        owner_function: global_sg.GlobalFunctionId,
        module_index: usize,
    ) !global_sg.GlobalNodeId {
        if (!self.replacement_candidates.contains(node_id)) return value;
        const binding = lexical_storage.root(self.graph, target) orelse return value;
        // Module-level storage has no lexical cleanup activation.
        if (std.mem.indexOfScalar(global_sg.GlobalBindingId, visible, binding) == null) return value;
        const context = reach_context.Context.fromGlobal(visible, owner_function);
        try self.prepareAutoDeinit(binding, context, module_index);
        const ty = self.graph.node(target).ty orelse return value;
        const plan = try self.buildAutoDeinit(
            .{ .projected = .{ .binding = binding, .target = target } },
            target,
            ty,
            context,
            module_index,
        ) orelse return value;
        const id: global_sg.GlobalAutoDeinitId = @enumFromInt(@as(u32, @intCast(self.graph.auto_deinits.items.len)));
        try self.graph.auto_deinits.append(self.allocator, plan);
        const cleanup = try self.appendNode(self.graph.node(value).source, try self.builtin(.Void), .{ .auto_deinit_binding = id });
        return self.replacementValue(value, ty, cleanup);
    }

    fn indirectReplacement(self: *Resolver, node_id: global_sg.GlobalNodeId, target: global_sg.GlobalNodeId, value: global_sg.GlobalNodeId, visible: []const global_sg.GlobalBindingId, owner_function: global_sg.GlobalFunctionId, module_index: usize) !global_sg.GlobalNodeId {
        if (!self.replacement_candidates.contains(node_id)) return value;
        const ty = self.graph.node(target).ty orelse return value;
        const plan = try self.buildAutoDeinit(.{ .indirect = target }, target, ty, reach_context.Context.fromGlobal(visible, owner_function), module_index) orelse return value;
        const id: global_sg.GlobalAutoDeinitId = @enumFromInt(self.graph.auto_deinits.items.len);
        try self.graph.auto_deinits.append(self.allocator, plan);
        const cleanup = try self.appendNode(self.graph.node(value).source, try self.builtin(.Void), .{ .auto_deinit_binding = id });
        return self.replacementValue(value, ty, cleanup);
    }

    fn wrapReplacement(self: *Resolver, id: global_sg.GlobalNodeId) !void {
        const original = self.graph.node(id);
        const write = try self.appendNode(original.source, original.ty, original.content);
        const start: u32 = @intCast(self.graph.node_refs.items.len);
        try self.graph.node_refs.append(self.allocator, write);
        const block: global_sg.GlobalBlockId = @enumFromInt(self.graph.blocks.items.len);
        try self.graph.blocks.append(self.allocator, .{ .nodes = .{ .start = start, .len = 1 }, .ret_val = write });
        try self.graph.setNodeContent(self.allocator, id, .{ .replacement = block });
    }

    fn replacementValue(self: *Resolver, value: global_sg.GlobalNodeId, ty: global_sg.GlobalTypeId, cleanup: global_sg.GlobalNodeId) !global_sg.GlobalNodeId {
        const source = self.graph.node(value).source;
        const temporary: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.graph.bindings.items.len)));
        try self.graph.bindings.append(self.allocator, .{
            .name = try self.graph.addString(self.allocator, "_replacement"),
            .source = source,
            .ty = ty,
            .initialization = value,
            .mutability = .constant,
        });
        const declaration = try self.appendNode(source, null, .{ .binding_declaration = temporary });
        const use = try self.appendNode(source, ty, .{ .binding_use = temporary });
        const result = try self.appendNode(source, ty, .{ .move_value = use });
        const start: u32 = @intCast(self.graph.node_refs.items.len);
        try self.graph.node_refs.appendSlice(self.allocator, &.{ declaration, cleanup, result });
        const block: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(self.graph.blocks.items.len)));
        try self.graph.blocks.append(self.allocator, .{ .nodes = .{ .start = start, .len = 3 }, .ret_val = result });
        return self.appendNode(source, ty, .{ .value_sequence = block });
    }

    fn finalizeBlock(
        self: *Resolver,
        block_id: global_sg.GlobalBlockId,
        inherited_active: *std.ArrayList(global_sg.GlobalBindingId),
        inherited_defers: *std.ArrayList(global_sg.GlobalNodeId),
        inherited_visible: *std.ArrayList(global_sg.GlobalBindingId),
        introduced_bindings: []const global_sg.GlobalBindingId,
        owner_function: global_sg.GlobalFunctionId,
        module_index: usize,
        loop_cleanup: ?LoopCleanup,
    ) anyerror!void {
        const original = self.graph.blocks.items[@intFromEnum(block_id)];
        var active: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer active.deinit(self.allocator);
        try active.appendSlice(self.allocator, inherited_active.items);
        const active_base = active.items.len;
        var defers: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer defers.deinit(self.allocator);
        try defers.appendSlice(self.allocator, inherited_defers.items);
        const defer_base = defers.items.len;
        var visible: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer visible.deinit(self.allocator);
        try visible.appendSlice(self.allocator, inherited_visible.items);
        for (introduced_bindings) |binding| {
            try visible.append(self.allocator, binding);
            try self.prepareAutoDeinit(
                binding,
                reach_context.Context.fromGlobal(visible.items, owner_function),
                module_index,
            );
            try active.append(self.allocator, binding);
        }

        var rebuilt: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer rebuilt.deinit(self.allocator);
        // Recursive finalization appends cleanup edges to graph.node_refs and
        // may reallocate it. Keep a stable copy of this block's original node IDs.
        const nodes = try self.allocator.dupe(global_sg.GlobalNodeId, self.graph.node_refs.items[original.nodes.start..][0..original.nodes.len]);
        defer self.allocator.free(nodes);
        for (nodes) |node_id| {
            var temporaries: std.ArrayList(global_sg.GlobalNodeId) = .empty;
            defer temporaries.deinit(self.allocator);
            try self.collectDefaultTemporaries(self.deferValue(node_id) orelse node_id, &temporaries);
            for (temporaries.items) |declaration| {
                const binding = self.graph.node(declaration).content.binding_declaration;
                if (std.mem.indexOfScalar(global_sg.GlobalBindingId, active.items, binding) != null) continue;
                try rebuilt.append(self.allocator, declaration);
                try visible.append(self.allocator, binding);
                try self.prepareAutoDeinit(binding, reach_context.Context.fromGlobal(visible.items, owner_function), module_index);
                try active.append(self.allocator, binding);
            }
            try rebuilt.append(self.allocator, node_id);
            const content = self.graph.node(node_id).content;
            if (content != .code_block and content != .value_sequence and content != .replacement)
                try self.finalizeExpressionCleanup(node_id, active.items, defers.items, visible.items, owner_function, module_index, loop_cleanup);
            const node = self.graph.node(node_id);
            if (self.deferValue(node_id)) |deferred_value| {
                // The marker is a no-op, but the deferred body still owns
                // branch-local bindings and nested deferred actions.
                try self.finalizeExpressionCleanup(deferred_value, active.items, defers.items, visible.items, owner_function, module_index, loop_cleanup);
                try defers.append(self.allocator, deferred_value);
                continue;
            }
            switch (node.content) {
                .binding_declaration => |binding| {
                    try visible.append(self.allocator, binding);
                    try self.prepareAutoDeinit(
                        binding,
                        reach_context.Context.fromGlobal(visible.items, owner_function),
                        module_index,
                    );
                    const persistent = self.continuation_function == owner_function and
                        self.graph.function(owner_function).body == block_id;
                    if (!persistent) try active.append(self.allocator, binding);
                },
                .return_statement => {
                    const cleanup = try self.appendCleanup(active.items, defers.items);
                    var updated = node;
                    updated.content.return_statement.cleanup = cleanup;
                    try self.graph.setNode(self.allocator, node_id, updated);
                },
                .code_block, .value_sequence => |child| try self.finalizeBlock(child, &active, &defers, &visible, &.{}, owner_function, module_index, loop_cleanup),
                .if_statement => |statement| {
                    try self.finalizeBlock(statement.then_block, &active, &defers, &visible, &.{}, owner_function, module_index, loop_cleanup);
                    if (statement.else_block) |child|
                        try self.finalizeBlock(child, &active, &defers, &visible, &.{}, owner_function, module_index, loop_cleanup);
                },
                .while_statement, .for_statement => {
                    const body = if (node.content == .while_statement) node.content.while_statement.body else node.content.for_statement.body;
                    try self.finalizeBlock(body, &active, &defers, &visible, &.{}, owner_function, module_index, .{ .active = active.items.len, .defers = defers.items.len });
                },
                .break_statement, .continue_statement => {
                    if (loop_cleanup) |base| {
                        // Loop transfers end nested lexical scopes but retain the
                        // iterator owner in the surrounding loop scope.
                        const cleanup = try self.appendCleanup(active.items[base.active..], defers.items[base.defers..]);
                        _ = rebuilt.pop();
                        try rebuilt.appendSlice(self.allocator, self.graph.node_refs.items[cleanup.start..][0..cleanup.len]);
                        try rebuilt.append(self.allocator, node_id);
                    }
                },
                .switch_statement => |switch_id| {
                    const sw = self.graph.switches.items[@intFromEnum(switch_id)];
                    const cases = try self.allocator.dupe(global_sg.SwitchCase, self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]);
                    defer self.allocator.free(cases);
                    for (cases) |case| {
                        const bindings: []const global_sg.GlobalBindingId = if (case.payload_mode == .move)
                            if (case.payload_binding) |*binding| binding[0..1] else &.{}
                        else
                            &.{};
                        try self.finalizeBlock(case.body, &active, &defers, &visible, bindings, owner_function, module_index, loop_cleanup);
                    }
                    if (sw.default_block) |child|
                        try self.finalizeBlock(child, &active, &defers, &visible, &.{}, owner_function, module_index, loop_cleanup);
                },
                else => {},
            }
        }

        // Normal scope exit executes only cleanup introduced by this block.
        var local_cleanup: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer local_cleanup.deinit(self.allocator);
        var i = defers.items.len;
        while (i > defer_base) {
            i -= 1;
            try local_cleanup.append(self.allocator, defers.items[i]);
        }
        i = active.items.len;
        while (i > active_base) {
            i -= 1;
            if (self.autoDeinitNode(active.items[i])) |node| try local_cleanup.append(self.allocator, node);
        }
        try rebuilt.appendSlice(self.allocator, local_cleanup.items);

        const start: u32 = @intCast(self.graph.node_refs.items.len);
        try self.graph.node_refs.appendSlice(self.allocator, rebuilt.items);
        {
            var updated = self.graph.blocks.items[@intFromEnum(block_id)];
            updated.nodes = .{ .start = start, .len = @intCast(rebuilt.items.len) };
            try self.graph.setBlock(self.allocator, block_id, updated);
        }
        if (local_cleanup.items.len != 0) self.stats.cleanup_edges += @intCast(local_cleanup.items.len);
    }

    /// Reuse selected cleanup in reverse binding order for an explicit session
    /// exit. This selects no new destructor and publishes no runtime behavior.
    /// The coordinator must check the resulting exit command against retained
    /// temporal facts before executing it or discarding session storage.
    pub fn selectedSessionCleanup(self: *const Resolver, allocator: std.mem.Allocator, bindings: []const global_sg.GlobalBindingId) ![]global_sg.GlobalNodeId {
        var result: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        errdefer result.deinit(allocator);
        var index = bindings.len;
        while (index != 0) {
            index -= 1;
            const binding = bindings[index];
            if (std.mem.indexOfScalar(global_sg.GlobalBindingId, bindings[0..index], binding) != null) return error.DuplicateSessionBinding;
            var found = false;
            for (self.auto_nodes.items) |entry| if (entry.binding == binding) {
                found = true;
                if (entry.node) |node| try result.append(allocator, node);
                break;
            };
            if (!found) return error.UnknownSessionCleanup;
        }
        return result.toOwnedSlice(allocator);
    }

    fn appendCleanup(
        self: *Resolver,
        active: []const global_sg.GlobalBindingId,
        defers: []const global_sg.GlobalNodeId,
    ) !primitives.Range(global_sg.GlobalNodeId) {
        const start: u32 = @intCast(self.graph.node_refs.items.len);
        var count: u32 = 0;
        var i = defers.len;
        while (i != 0) {
            i -= 1;
            try self.graph.node_refs.append(self.allocator, defers[i]);
            count += 1;
        }
        i = active.len;
        while (i != 0) {
            i -= 1;
            if (self.autoDeinitNode(active[i])) |node| {
                try self.graph.node_refs.append(self.allocator, node);
                count += 1;
            }
        }
        self.stats.cleanup_edges += count;
        return .{ .start = start, .len = count };
    }

    fn autoDeinitNode(self: *const Resolver, binding: global_sg.GlobalBindingId) ?global_sg.GlobalNodeId {
        for (self.auto_nodes.items) |entry| if (entry.binding == binding) return entry.node;
        return null;
    }

    /// Reuse lexical evidence without bypassing implicit-copy permission or
    /// allowing an inherited assumption to override a local binding.
    pub fn inheritAssumedFields(
        self: *Resolver,
        source: primitives.SourceRef,
        original: primitives.Range(global_sg.GlobalValueFieldId),
        assumptions: []const global_sg.GlobalBindingId,
        visible: []const global_sg.GlobalBindingId,
    ) !primitives.Range(global_sg.GlobalValueFieldId) {
        if (assumptions.len == 0) return original;
        var fields: std.ArrayList(global_sg.ValueField) = .empty;
        defer fields.deinit(self.allocator);
        try fields.appendSlice(self.allocator, self.graph.value_fields.items[original.start..][0..original.len]);
        for (assumptions) |binding| {
            const value = self.graph.binding(binding);
            var shadowed = false;
            for (fields.items) |field| {
                if (std.mem.eql(u8, self.graph.text(field.name), self.graph.text(value.name))) shadowed = true;
            }
            for (visible) |local| {
                if (local != binding and std.mem.eql(u8, self.graph.text(self.graph.binding(local).name), self.graph.text(value.name))) shadowed = true;
            }
            if (shadowed) continue;
            const use = try self.appendNode(source, value.ty, .{ .binding_use = binding });
            const copy = try self.appendNode(source, value.ty, .{ .binding_use = binding });
            if (!try self.resolveGlobalCopy(use, copy)) return error.InvalidSafetyContinuation;
            try fields.append(self.allocator, .{ .name = value.name, .value = copy });
        }
        const start: u32 = @intCast(self.graph.value_fields.items.len);
        try self.graph.value_fields.appendSlice(self.allocator, fields.items);
        return .{ .start = start, .len = @intCast(fields.items.len) };
    }

    fn prepareAutoDeinit(
        self: *Resolver,
        binding: global_sg.GlobalBindingId,
        context: reach_context.Context,
        module_index: usize,
    ) !void {
        for (self.auto_nodes.items) |entry| if (entry.binding == binding) return;
        if (self.graph.isBindingTypeUnresolved(binding)) return error.UnresolvedAutoDeinitBinding;
        const record = self.graph.bindings.items[@intFromEnum(binding)];
        const target = try self.appendNode(record.source, record.ty, .{ .binding_use = binding });
        var cleanup_context = context;
        if (record.cleanup_arguments) |input| {
            cleanup_context.global.assumed_fields = self.graph.nodes.items[@intFromEnum(input)].content.struct_value_literal.assumed_fields;
        }
        if (self.continuation_function != null and context.ownerFunction() == self.continuation_function) {
            if (self.core.session_namespace) |namespace| {
                cleanup_context.global.assumed_fields = try self.inheritAssumedFields(
                    record.source,
                    cleanup_context.global.assumed_fields,
                    namespace.assumptions.items,
                    context.global.visible_bindings,
                );
            }
        }
        const descriptor = try self.buildAutoDeinit(
            .{ .binding = binding },
            target,
            record.ty,
            cleanup_context,
            module_index,
        );
        var cleanup_node: ?global_sg.GlobalNodeId = null;
        if (descriptor) |resolved| {
            const auto_id: global_sg.GlobalAutoDeinitId = @enumFromInt(@as(u32, @intCast(self.graph.auto_deinits.items.len)));
            try self.graph.auto_deinits.append(self.allocator, resolved);
            cleanup_node = try self.appendNode(record.source, try self.builtin(.Void), .{ .auto_deinit_binding = auto_id });
            self.stats.auto_deinits += 1;
        }
        if (record.deferred_initialization) {
            var updated = self.graph.bindings.items[@intFromEnum(binding)];
            updated.reinitialize_cleanup = cleanup_node;
            try self.graph.setBinding(self.allocator, binding, updated);
        }
        try self.auto_nodes.append(self.allocator, .{ .binding = binding, .node = cleanup_node });
    }

    fn buildAutoDeinit(
        self: *Resolver,
        storage: @FieldType(global_sg.AutoDeinit, "storage"),
        target: global_sg.GlobalNodeId,
        ty: global_sg.GlobalTypeId,
        context: reach_context.Context,
        module_index: usize,
    ) !?global_sg.AutoDeinit {
        // References never own their pointee.
        if (self.graph.semanticType(ty) == .pointer) return null;
        if (try self.resolveDestructor(target, context, module_index)) |resolved| {
            // A complete aggregate can later lose fields or payload members
            // through a borrow. Keep its structural alternative from the start:
            // incomplete storage cannot run the nominal whole-value destructor.
            return .{
                .storage = storage,
                .deinit_fn = resolved.function,
                .input = resolved.input,
                .self_field_index = resolved.self_field_index,
                .fields = if (global_types.fields(self.graph, ty) != null or global_types.variants(self.graph, ty) != null or global_types.arrayElement(self.graph, ty) != null)
                    try self.buildAutoChildren(target, ty, context, module_index)
                else
                    .{ .start = 0, .len = 0 },
            };
        }

        const children = try self.buildAutoChildren(target, ty, context, module_index);
        if (children.len == 0) return null;
        return .{ .storage = storage, .deinit_fn = null, .fields = children };
    }

    fn buildAutoField(
        self: *Resolver,
        field_index: u32,
        target: global_sg.GlobalNodeId,
        ty: global_sg.GlobalTypeId,
        context: reach_context.Context,
        module_index: usize,
    ) anyerror!?global_sg.AutoDeinitField {
        if (self.graph.semanticType(ty) == .pointer) return null;
        if (try self.resolveDestructor(target, context, module_index)) |resolved| {
            return .{
                .field_index = field_index,
                .deinit_fn = resolved.function,
                .input = resolved.input,
                .self_field_index = resolved.self_field_index,
                .fields = if (global_types.fields(self.graph, ty) != null or global_types.variants(self.graph, ty) != null or global_types.arrayElement(self.graph, ty) != null)
                    try self.buildAutoChildren(target, ty, context, module_index)
                else
                    .{ .start = 0, .len = 0 },
            };
        }
        const children = try self.buildAutoChildren(target, ty, context, module_index);
        if (children.len == 0) return null;
        return .{ .field_index = field_index, .deinit_fn = null, .fields = children };
    }

    fn buildAutoChildren(
        self: *Resolver,
        target: global_sg.GlobalNodeId,
        ty: global_sg.GlobalTypeId,
        context: reach_context.Context,
        module_index: usize,
    ) anyerror!primitives.Range(global_sg.GlobalAutoDeinitFieldId) {
        var children: std.ArrayList(global_sg.AutoDeinitField) = .empty;
        defer children.deinit(self.allocator);
        const source = self.graph.node(target).source;
        // Choices own only their active payload. Preserve the variant projection
        // in cleanup metadata so every consumer observes the same condition.
        if (global_types.arrayElement(self.graph, ty)) |element| {
            const length = global_types.arrayLength(self.graph, ty).?;
            if (length != 0) {
                const pointer_type = try self.core.pointerType(ty, .read_write);
                const pointer = try self.appendNode(source, pointer_type, .{ .address_of = target });
                const index = try self.appendNode(source, try self.builtin(.UIntNative), .{ .int_literal = 0 });
                const projected = try self.appendNode(source, element, .{ .array_index = .{ .array_ptr = pointer, .index = index, .element_type = element, .array_type = ty } });
                if (try self.buildAutoField(0, projected, element, context, module_index)) |selected| {
                    var child = selected;
                    child.repeat_count = length;
                    try children.append(self.allocator, child);
                }
            }
        } else if (global_types.variants(self.graph, ty)) |variants| {
            for (0..variants.len) |index| {
                const id: global_sg.GlobalVariantId = @enumFromInt(variants.start + @as(u32, @intCast(index)));
                const variant = self.graph.variants.items[@intFromEnum(id)];
                const payload = variant.payload_type orelse continue;
                const projected = try self.appendNode(source, payload, .{ .choice_payload_access = .{
                    .value = target,
                    .variant = id,
                    .payload_type = payload,
                } });
                if (try self.buildAutoField(@intCast(index), projected, payload, context, module_index)) |resolved| {
                    var child = resolved;
                    child.is_variant = true;
                    try children.append(self.allocator, child);
                }
            }
        } else if (global_types.fields(self.graph, ty)) |fields| {
            for (0..fields.len) |index| {
                const field = self.graph.fields.items[fields.start + @as(u32, @intCast(index))];
                const projected = try self.appendNode(source, field.ty, .{ .struct_field_access = .{
                    .value = target,
                    .field_name = field.name,
                    .field_index = @intCast(index),
                } });
                if (try self.buildAutoField(@intCast(index), projected, field.ty, context, module_index)) |child|
                    try children.append(self.allocator, child);
            }
        }
        const start: u32 = @intCast(self.graph.auto_deinit_fields.items.len);
        try self.graph.auto_deinit_fields.appendSlice(self.allocator, children.items);
        return .{ .start = start, .len = @intCast(children.items.len) };
    }

    fn resolveDestructor(
        self: *Resolver,
        target: global_sg.GlobalNodeId,
        context: reach_context.Context,
        module_index: usize,
    ) !?ResolvedDestructor {
        if (try self.resolveDestructorInScope(target, context, module_index)) |call| return call;
        const ty = self.graph.node(target).ty orelse return null;
        const owner = global_types.nominalTypeOwner(self.graph, ty) orelse return null;
        if (@intFromEnum(owner) == module_index or self.graph.modules.items[@intFromEnum(owner)].is_bundled_core) return null;
        // A resource keeps its defining module's cleanup when passed to a
        // caller in another module. Reached arguments still come from the
        // caller's captured context, not from the defining module's locals.
        return self.resolveDestructorInScope(target, context, @intFromEnum(owner));
    }

    fn resolveDestructorInScope(
        self: *Resolver,
        target: global_sg.GlobalNodeId,
        context: reach_context.Context,
        module_index: usize,
    ) !?ResolvedDestructor {
        const profile_start = self.profileNow();
        var succeeded = false;
        defer if (self.profile_io) |io| {
            self.profile_destructor_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - profile_start;
            self.profile_destructor_calls += 1;
            if (succeeded)
                self.stats.destructor_successes += 1
            else
                self.stats.destructor_failures += 1;
        };
        const target_ty = self.graph.nodes.items[@intFromEnum(target)].ty orelse return null;
        const dispatch = self.dispatch orelse return error.MissingOwnershipDispatch;
        const pointer_ty = try self.core.pointerType(target_ty, .read_write);
        const source = self.graph.nodes.items[@intFromEnum(target)].source;
        const address = try self.appendNode(source, pointer_ty, .{ .address_of = target });

        if (standard_contracts.standardDeclaration(self.graph, "Deinit")) |declaration| {
            if (try dispatch.contracts.implements(target_ty, declaration)) {
                const input = try self.singleNamedInput("self", address, source);
                if (context == .global) {
                    var updated = self.graph.node(input);
                    updated.content.struct_value_literal.assumed_fields = context.global.assumed_fields;
                    try self.graph.setNode(self.allocator, input, updated);
                }
                var participants = [_]global_sg.GlobalTypeId{target_ty};
                const node = try dispatch.contracts.callOperationCandidate(module_index, .{
                    .declaration = declaration,
                    .participants = &participants,
                }, "deinit", input, context, source) orelse return error.DeferredImplicitFunction;
                const call = node.content.function_call;
                succeeded = true;
                return .{ .function = call.callee, .input = call.input, .self_field_index = 0 };
            }
        }

        return null;
    }

    fn singleNamedInput(
        self: *Resolver,
        name: []const u8,
        value: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) !global_sg.GlobalNodeId {
        const field_start: u32 = @intCast(self.graph.value_fields.items.len);
        try self.graph.value_fields.append(self.allocator, .{
            .name = try self.graph.addString(self.allocator, name),
            .value = value,
        });
        return self.appendNode(source, null, .{ .struct_value_literal = .{
            .fields = .{ .start = field_start, .len = 1 },
        } });
    }

    fn appendNode(
        self: *Resolver,
        source: primitives.SourceRef,
        ty: ?global_sg.GlobalTypeId,
        content: global_sg.Node.Content,
    ) !global_sg.GlobalNodeId {
        const id: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{ .source = source, .ty = ty, .content = content });
        return id;
    }

    fn triviallyCopyable(self: *Resolver, ty: global_sg.GlobalTypeId) bool {
        if (global_types.deinitFunction(self.graph, ty) != null) return false;
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .builtin, .definition, .pointer, .virtual => true,
            .array => |array| self.triviallyCopyable(array.element),
            .structural => blk: {
                const fields = global_types.fields(self.graph, ty) orelse break :blk false;
                for (self.graph.fields.items[fields.start..][0..fields.len]) |field|
                    if (!self.triviallyCopyable(field.ty)) break :blk false;
                break :blk true;
            },
            .declared => |id| blk: {
                if (self.graph.declaration(id).underlying_type) |underlying| break :blk self.triviallyCopyable(underlying);
                if (self.graph.declaration(id).struct_layout == .c_function_pointer) break :blk true;
                if (global_types.fields(self.graph, ty)) |fields|
                    break :blk self.fieldsTriviallyCopyable(fields);
                if (global_types.variants(self.graph, ty)) |variants|
                    break :blk self.variantsTriviallyCopyable(variants);
                break :blk false;
            },
            .generic => blk: {
                const instance = global_types.genericInstance(self.graph, ty) orelse break :blk false;
                break :blk switch (instance.shape) {
                    .structure => |shape| self.fieldsTriviallyCopyable(shape.fields),
                    .choice => |shape| self.variantsTriviallyCopyable(shape.variants),
                    .array => |shape| self.triviallyCopyable(shape.element),
                    .alias => |target| self.triviallyCopyable(target),
                };
            },
            .structural_choice, .inferred_choice => blk: {
                const variants = global_types.variants(self.graph, ty) orelse break :blk false;
                break :blk self.variantsTriviallyCopyable(variants);
            },
            .nullable, .inferred_errable => |child| self.triviallyCopyable(child),
        };
    }

    fn fieldsTriviallyCopyable(self: *Resolver, fields: global_sg.FieldRange) bool {
        for (self.graph.fields.items[fields.start..][0..fields.len]) |field|
            if (!self.triviallyCopyable(field.ty)) return false;
        return true;
    }

    fn variantsTriviallyCopyable(self: *Resolver, variants: global_sg.VariantRange) bool {
        for (self.graph.variants.items[variants.start..][0..variants.len]) |variant|
            if (variant.payload_type) |payload| if (!self.triviallyCopyable(payload)) return false;
        return true;
    }

    fn deferValue(self: *const Resolver, marker: global_sg.GlobalNodeId) ?global_sg.GlobalNodeId {
        for (self.deferred.items) |entry| if (entry.marker == marker) return entry.value;
        return null;
    }

    fn makeNoop(self: *Resolver, marker: global_sg.GlobalNodeId, source: primitives.SourceRef) !void {
        const block = if (self.empty_block) |id| id else blk: {
            const id: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(self.graph.blocks.items.len)));
            try self.graph.blocks.append(self.allocator, .{ .nodes = .{ .start = @intCast(self.graph.node_refs.items.len), .len = 0 }, .ret_val = null });
            self.empty_block = id;
            break :blk id;
        };
        try self.graph.setNode(self.allocator, marker, .{
            .source = source,
            .ty = try self.builtin(.Void),
            .content = .{ .code_block = block },
        });
    }

    fn builtin(self: *Resolver, wanted: primitives.BuiltinType) !global_sg.GlobalTypeId {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .builtin => |value| if (value == wanted) return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .builtin = wanted });
        return id;
    }
};

fn globalSource(o: globalizer.Offsets, source: primitives.SourceRef) primitives.SourceRef {
    return .{ .file_index = o.file_base + source.file_index, .offset = source.offset };
}

fn typeAccepts(graph: *const global_sg.GlobalSemanticGraph, expected: global_sg.GlobalTypeId, concrete: global_sg.GlobalTypeId) bool {
    if (global_types.equal(graph, expected, concrete)) return true;
    return switch (graph.types.items[@intFromEnum(expected)]) {
        .pointer => |pointer| global_types.equal(graph, pointer.child, concrete),
        else => false,
    };
}

test "ownership cleanup resolver stores cleanup as GlobalNodeId edges" {
    try std.testing.expect(@sizeOf(global_sg.GlobalAutoDeinitId) == 4);
    try std.testing.expect(@sizeOf(global_sg.GlobalNodeId) == 4);
}

test "error propagation cleanup captures active lexical obligations" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    const int_ty: global_sg.GlobalTypeId = @enumFromInt(0);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const empty = try graph.addString(allocator, "");

    const deferred_node: global_sg.GlobalNodeId = @enumFromInt(0);
    const propagation_node: global_sg.GlobalNodeId = @enumFromInt(1);
    const assignment_node: global_sg.GlobalNodeId = @enumFromInt(2);
    try graph.nodes.append(allocator, .{
        .source = source,
        .ty = int_ty,
        .content = .{ .int_literal = 0 },
    });
    try graph.error_propagations.append(allocator, .{
        .errable_value = deferred_node,
        .cleanup_nodes = .{ .start = 0, .len = 0 },
        .ok_variant = @enumFromInt(0),
        .ok_value_field_index = null,
        .error_variant = @enumFromInt(0),
        .propagated_errable_type = int_ty,
        .propagated_error_variant = @enumFromInt(0),
        .ok_payload_type = int_ty,
        .error_payload_type = int_ty,
        .propagated_error_payload_type = int_ty,
        .diagnostic_line = 0,
        .diagnostic_column = 0,
        .diagnostic_source_line = empty,
    });
    try graph.nodes.append(allocator, .{
        .source = source,
        .ty = int_ty,
        .content = .{ .error_propagation = @enumFromInt(0) },
    });
    try graph.bindings.append(allocator, .{
        .name = empty,
        .source = source,
        .ty = int_ty,
        .mutability = .variable,
    });
    try graph.nodes.append(allocator, .{
        .source = source,
        .ty = int_ty,
        .content = .{ .assignment = .{ .binding = @enumFromInt(0), .value = propagation_node } },
    });

    var core: core_mod.Resolver = .{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
    };
    var resolver: Resolver = .{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
        .core = &core,
    };
    defer resolver.deinit();

    try resolver.finalizeExpressionCleanup(assignment_node, &.{}, &.{deferred_node}, &.{}, @enumFromInt(0), 0, null);
    const cleanup = graph.error_propagations.items[0].cleanup_nodes;
    try std.testing.expectEqual(@as(u32, 1), cleanup.len);
    try std.testing.expectEqual(deferred_node, graph.node_refs.items[cleanup.start]);
}

test "parameterized defer checkpoint restores resolver side effects" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var core = core_mod.Resolver{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
    };
    var resolver = Resolver{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
        .core = &core,
    };
    defer resolver.deinit();

    try resolver.deferred.append(allocator, .{ .marker = @enumFromInt(1), .value = @enumFromInt(2) });
    resolver.stats.defers = 1;
    resolver.empty_block = @enumFromInt(7);
    const saved = Resolver.parameterizedCheckpoint(&resolver);

    try resolver.deferred.append(allocator, .{ .marker = @enumFromInt(3), .value = @enumFromInt(4) });
    resolver.stats.defers = 2;
    resolver.empty_block = @enumFromInt(8);
    try resolver.markReplacement(@enumFromInt(33));
    try resolver.auto_nodes.append(allocator, .{ .binding = @enumFromInt(0), .node = @enumFromInt(34) });
    Resolver.rollbackParameterizedCheckpoint(&resolver, saved);
    try std.testing.expectEqual(@as(global_sg.GlobalBlockId, @enumFromInt(7)), resolver.empty_block.?);
    try std.testing.expectEqual(@as(usize, 0), resolver.auto_nodes.items.len);
    try std.testing.expect(!resolver.replacement_candidates.contains(@enumFromInt(33)));

    try std.testing.expectEqual(@as(usize, 1), resolver.deferred.items.len);
    try std.testing.expectEqual(@as(u32, 1), resolver.stats.defers);
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(resolver.deferred.items[0].marker));
}

test "session exit cleanup reuses selected nodes in reverse declaration order" {
    const a = std.testing.allocator;
    var resolver: Resolver = .{ .allocator = a, .graph = undefined, .modules = &.{}, .offsets = &.{}, .core = undefined };
    defer resolver.deinit();
    try resolver.auto_nodes.appendSlice(a, &.{
        .{ .binding = @enumFromInt(0), .node = @enumFromInt(10) },
        .{ .binding = @enumFromInt(1), .node = null },
        .{ .binding = @enumFromInt(2), .node = @enumFromInt(12) },
    });
    const nodes = try resolver.selectedSessionCleanup(a, &.{ @enumFromInt(0), @enumFromInt(1), @enumFromInt(2) });
    defer a.free(nodes);
    try std.testing.expectEqualSlices(global_sg.GlobalNodeId, &.{ @enumFromInt(12), @enumFromInt(10) }, nodes);
    try std.testing.expectError(error.DuplicateSessionBinding, resolver.selectedSessionCleanup(a, &.{ @enumFromInt(0), @enumFromInt(0) }));
    try std.testing.expectError(error.UnknownSessionCleanup, resolver.selectedSessionCleanup(a, &.{@enumFromInt(9)}));
}
