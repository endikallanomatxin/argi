const std = @import("std");
const g = @import("graph.zig");
const ir = @import("../module/parameterized/ir.zig");
const Generics = @import("generics.zig").Resolver;
const Functions = @import("generic_functions.zig").Resolver;
const TypeRecipe = @import("type_recipe.zig").Recipe;
const reachability = @import("reachability.zig");

// Requests retain recipes independently of speculative graph tails. Only this
// coordinator publishes executable nodes, between ordinary resolution passes.
// Transient types are captured as owned descriptions; only the coordinator
// publishes reconstructed identities outside a losing selection's rollback.
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    functions: *Functions,
    stable_type_count: usize,
    stable_declaration_count: usize = 0,
    stable_type_definition_count: usize = 0,
    stable_family_definition_count: usize = 0,
    stable_node_count: usize = 0,
    requests: std.ArrayList(Request) = .empty,
    // Sparse descriptions do not enlarge every ordinary request record.
    type_recipes: std.ArrayList(TypeRecipe) = .empty,
    rewrites: std.ArrayList(RequestRewrite) = .empty,

    const RequestRewrite = struct { index: usize, node: ?g.GlobalNodeId, value: ?Value, types_published: bool };
    pub const StateCheckpoint = struct {
        requests: usize,
        recipes: usize,
        rewrites: usize,
        stable_types: usize,
        stable_declarations: usize,
        stable_type_definitions: usize = 0,
        stable_family_definitions: usize = 0,
        stable_nodes: usize,
    };

    const Request = struct {
        module: usize,
        expression: ir.ParameterizedNodeId,
        bindings: Generics.Bindings,
        node: ?g.GlobalNodeId = null,
        kind: Kind = .integer,
        value: ?Value = null,
        type_recipe: ?u32 = null,
        types_published: bool = true,
    };

    const Kind = enum { integer, boolean };
    const Value = union(Kind) { integer: i64, boolean: bool };

    /// Retain recipes and frozen results in an independently owned candidate.
    /// The caller supplies the resolver bound to its cloned semantic graph;
    /// materialized node/type identities remain valid because graph IDs match.
    pub fn clone(self: *const Scheduler, allocator: std.mem.Allocator, functions: *Functions) !Scheduler {
        var result: Scheduler = .{ .allocator = allocator, .functions = functions, .stable_type_count = self.stable_type_count, .stable_declaration_count = self.stable_declaration_count, .stable_type_definition_count = self.stable_type_definition_count, .stable_family_definition_count = self.stable_family_definition_count, .stable_node_count = self.stable_node_count };
        errdefer result.deinit();
        for (self.type_recipes.items) |*recipe| {
            var copy = try recipe.clone(allocator);
            result.type_recipes.append(allocator, copy) catch |err| {
                copy.deinit(allocator);
                return err;
            };
        }
        for (self.requests.items) |request| {
            try result.enqueue(request.module, request.expression, &request.bindings, request.kind);
            const retained = &result.requests.items[result.requests.items.len - 1];
            retained.node = request.node;
            retained.value = request.value;
            retained.type_recipe = request.type_recipe;
            retained.types_published = request.types_published;
        }
        try result.rewrites.appendSlice(allocator, self.rewrites.items);
        return result;
    }

    pub fn deinit(self: *Scheduler) void {
        for (self.requests.items) |*request| request.bindings.deinit(self.allocator);
        self.requests.deinit(self.allocator);
        for (self.type_recipes.items) |*recipe| recipe.deinit(self.allocator);
        self.type_recipes.deinit(self.allocator);
        self.rewrites.deinit(self.allocator);
    }

    /// A session checkpoint covers completions as well as appended requests.
    /// Probe callbacks below intentionally retain their narrower enqueue boundary.
    pub fn checkpointState(self: *const Scheduler) StateCheckpoint {
        return .{ .requests = self.requests.items.len, .recipes = self.type_recipes.items.len, .rewrites = self.rewrites.items.len, .stable_types = self.stable_type_count, .stable_declarations = self.stable_declaration_count, .stable_type_definitions = self.stable_type_definition_count, .stable_family_definitions = self.stable_family_definition_count, .stable_nodes = self.stable_node_count };
    }

    pub fn rollbackState(self: *Scheduler, saved: StateCheckpoint) void {
        while (self.rewrites.items.len > saved.rewrites) {
            const previous = self.rewrites.pop().?;
            const request = &self.requests.items[previous.index];
            request.node = previous.node;
            request.value = previous.value;
            request.types_published = previous.types_published;
            // An unpublished recipe has no retained transient type IDs.
            if (!previous.types_published) @memset(request.bindings.types, null);
        }
        for (self.requests.items[saved.requests..]) |*request| request.bindings.deinit(self.allocator);
        self.requests.shrinkRetainingCapacity(saved.requests);
        for (self.type_recipes.items[saved.recipes..]) |*recipe| recipe.deinit(self.allocator);
        self.type_recipes.shrinkRetainingCapacity(saved.recipes);
        self.stable_type_count = saved.stable_types;
        self.stable_declaration_count = saved.stable_declarations;
        self.stable_type_definition_count = saved.stable_type_definitions;
        self.stable_family_definition_count = saved.stable_family_definitions;
        self.stable_node_count = saved.stable_nodes;
    }

    pub fn commitState(self: *Scheduler) void {
        self.rewrites.deinit(self.allocator);
        self.rewrites = .empty;
    }

    fn recordRequest(self: *Scheduler, index: usize) !void {
        const request = self.requests.items[index];
        try self.rewrites.append(self.allocator, .{ .index = index, .node = request.node, .value = request.value, .types_published = request.types_published });
    }

    pub fn checkpoint(context: *anyopaque) usize {
        const self: *Scheduler = @ptrCast(@alignCast(context));
        return self.requests.items.len;
    }

    pub fn rollback(context: *anyopaque, saved: usize) void {
        const self: *Scheduler = @ptrCast(@alignCast(context));
        var first_recipe = self.type_recipes.items.len;
        for (self.requests.items[saved..]) |*request| {
            std.debug.assert(request.node == null);
            request.bindings.deinit(self.allocator);
            if (request.type_recipe) |id| first_recipe = @min(first_recipe, id);
        }
        for (self.type_recipes.items[first_recipe..]) |*recipe| recipe.deinit(self.allocator);
        self.type_recipes.shrinkRetainingCapacity(first_recipe);
        self.requests.shrinkRetainingCapacity(saved);
    }

    pub fn integer(context: *anyopaque, module: usize, expression: ir.ParameterizedNodeId, bindings: *const Generics.Bindings) anyerror!i64 {
        return (try requestValue(context, module, expression, bindings, .integer)).integer;
    }

    pub fn boolean(context: *anyopaque, module: usize, expression: ir.ParameterizedNodeId, bindings: *const Generics.Bindings) anyerror!bool {
        return (try requestValue(context, module, expression, bindings, .boolean)).boolean;
    }

    fn requestValue(context: *anyopaque, module: usize, expression: ir.ParameterizedNodeId, bindings: *const Generics.Bindings, kind: Kind) !Value {
        const self: *Scheduler = @ptrCast(@alignCast(context));
        for (self.requests.items) |request| {
            if (request.module != module or request.expression != expression or request.kind != kind) continue;
            if (!std.mem.eql(?i64, request.bindings.ints, bindings.ints)) continue;
            if (request.type_recipe) |id| {
                if (!try self.type_recipes.items[id].matches(self.allocator, self.functions.graph, bindings.types)) continue;
            } else if (!std.mem.eql(?g.GlobalTypeId, request.bindings.types, bindings.types)) continue;
            return request.value orelse error.ComptimeExecutionPending;
        }
        const temporary = for (bindings.types) |ty| {
            if (ty) |id| if (@intFromEnum(id) >= self.stable_type_count) break true;
        } else false;
        var types: ?TypeRecipe = if (temporary) TypeRecipe.capture(self.allocator, self.functions.graph, .{ .types = self.stable_type_count, .declarations = self.stable_declaration_count, .type_definitions = self.stable_type_definition_count, .family_definitions = self.stable_family_definition_count, .nodes = self.stable_node_count }, bindings.types) catch |err| switch (err) {
            error.ComptimeTypeRecipePending => return error.ComptimeExecutionPending,
            else => return err,
        } else null;
        errdefer if (types) |*owned| owned.deinit(self.allocator);
        const recipe_id = if (types != null) blk: {
            const id = std.math.cast(u32, self.type_recipes.items.len) orelse return error.SemanticGraphTooLarge;
            try self.type_recipes.ensureUnusedCapacity(self.allocator, 1);
            break :blk id;
        } else null;
        try self.enqueue(module, expression, bindings, kind);
        const request = &self.requests.items[self.requests.items.len - 1];
        request.type_recipe = recipe_id;
        request.types_published = types == null;
        // No temporary type ID may remain in the retained substitution table.
        if (types) |owned| {
            self.type_recipes.appendAssumeCapacity(owned);
            @memset(request.bindings.types, null);
        }
        types = null; // The retained sparse pool owns the suspended description.
        return error.ComptimeExecutionPending;
    }

    fn enqueue(self: *Scheduler, module: usize, expression: ir.ParameterizedNodeId, bindings: *const Generics.Bindings, kind: Kind) !void {
        const types = try self.allocator.dupe(?g.GlobalTypeId, bindings.types);
        errdefer self.allocator.free(types);
        const ints = try self.allocator.dupe(?i64, bindings.ints);
        errdefer self.allocator.free(ints);
        try self.requests.append(self.allocator, .{ .module = module, .expression = expression, .kind = kind, .bindings = .{ .types = types, .ints = ints } });
    }

    pub fn materialize(self: *Scheduler) !bool {
        var changed = false;
        const count = self.requests.items.len;
        for (0..count) |index| {
            // Instantiation can request other integers and grow this table.
            if (self.requests.items[index].node != null) continue;
            if (!self.requests.items[index].types_published) {
                var publication = self.functions.beginSpeculation();
                defer publication.deinit();
                const request = self.requests.items[index];
                const published = try self.allocator.alloc(?g.GlobalTypeId, request.bindings.types.len);
                defer self.allocator.free(published);
                // Materializing a generic choice default can suspend on another
                // compile-time dependency and grow either coordinator pool.
                // Borrow the owned recipe buffers through a copied descriptor.
                const recipe = self.type_recipes.items[request.type_recipe.?];
                recipe.publish(self.allocator, self.functions.generics, published) catch |err| switch (err) {
                    error.ComptimeExecutionPending => {
                        publication.retainPendingExecution();
                        continue;
                    },
                    error.ComptimeTypeRecipePending => continue,
                    else => return err,
                };
                try self.recordRequest(index);
                publication.commit();
                @memcpy(self.requests.items[index].bindings.types, published);
                self.requests.items[index].types_published = true;
                changed = true;
            }
            const request = self.requests.items[index];
            var speculation = self.functions.beginSpeculation();
            defer speculation.deinit();
            var bindings = Generics.Bindings{
                .types = try self.allocator.dupe(?g.GlobalTypeId, request.bindings.types),
                .ints = &.{},
            };
            defer bindings.deinit(self.allocator);
            bindings.ints = try self.allocator.dupe(?i64, request.bindings.ints);
            const node = self.functions.instantiateComptimeExpression(request.module, request.expression, &bindings) catch |err| switch (err) {
                error.ComptimeExecutionPending => {
                    speculation.retainPendingExecution();
                    continue;
                },
                // Module discovery may still append a declaration supplying
                // this call. An unresolved request remains a publication error
                // if discovery closes without satisfying it.
                error.UnboundComptimeParameter, error.UnboundGenericTypeParameter, error.UnresolvedParameterizedCall, error.UnresolvedParameterizedExpression, error.NoMatchingGenericFunction => continue,
                else => return err,
            };
            var registered = false;
            for (self.functions.graph.comptime_requests.items) |existing| if (existing == node) {
                registered = true;
                break;
            };
            if (!registered) try self.functions.graph.comptime_requests.append(self.allocator, node);
            try self.functions.graph.roots.append(self.allocator, node);
            try self.recordRequest(index);
            self.requests.items[index].node = node;
            speculation.commit();
            changed = true;
        }
        return changed or self.requests.items.len != count;
    }

    // A fixed point with unresolved execution demand is not a complete graph.
    // Do not hand absent dependency bodies to codegen or the final #run pass.
    pub fn diagnosePending(self: *Scheduler) bool {
        for (self.requests.items) |request| {
            if (request.value != null) continue;
            const source = if (request.node) |node| self.functions.graph.node(node).source else blk: {
                const storage = &self.functions.modules[request.module].semantic.parameterized_storage.ir;
                const local = storage.nodes.items[@intFromEnum(request.expression)];
                const relative: @import("../primitives/schema.zig").SourceRef = switch (local) {
                    .resolved => |node| node.source,
                    .pending => |pending| switch (storage.pending.items[@intFromEnum(pending)]) {
                        .resolve_name => |value| value.source,
                        .resolve_call => |value| value.source,
                        .resolve_field => |value| value.source,
                        .resolve_expression => |value| value.source,
                        else => .{ .file_index = 0, .offset = 0 },
                    },
                };
                break :blk @import("../primitives/schema.zig").SourceRef{ .file_index = self.functions.offsets[request.module].file_base + relative.file_index, .offset = relative.offset };
            };
            self.functions.generics.comptime_failure = .{ .source = source, .reason = "compile-time evaluation has unresolved or cyclic semantic dependencies" };
            return true;
        }
        return false;
    }

    pub fn evaluateReady(self: *Scheduler, contracts: *@import("contracts.zig").Resolver, diagnostics: ?*@import("../../1_base/diagnostic.zig").Diagnostics, finalized: *const std.AutoHashMap(g.GlobalFunctionId, void), pending_bodies: *const std.AutoHashMap(g.GlobalFunctionId, void)) !bool {
        if (self.requests.items.len == 0) return false;
        if (diagnostics) |sink| return self.evaluateReadyWithDiagnostics(contracts, sink, finalized, pending_bodies);
        // Proof and execution cannot depend on whether a caller wants diagnostic
        // text. A private bag retains failures until the evaluator returns.
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fallback = try @import("../../1_base/diagnostic.zig").Diagnostics.init(&a, &.{});
        defer fallback.deinit();
        return self.evaluateReadyWithDiagnostics(contracts, &fallback, finalized, pending_bodies);
    }

    fn evaluateReadyWithDiagnostics(self: *Scheduler, contracts: *@import("contracts.zig").Resolver, diagnostics: *@import("../../1_base/diagnostic.zig").Diagnostics, finalized: *const std.AutoHashMap(g.GlobalFunctionId, void), pending_bodies: *const std.AutoHashMap(g.GlobalFunctionId, void)) !bool {
        var changed = false;
        const graph = self.functions.graph;
        for (self.requests.items, 0..) |request, index| {
            if (request.value != null) continue;
            const node = request.node orelse continue;
            var unit = try reachability.expressionUnit(self.allocator, graph, node);
            defer unit.deinit();
            var functions = unit.values.keyIterator();
            var ready = true;
            while (functions.next()) |function| {
                if (pending_bodies.contains(function.*) or (graph.function(function.*).flags.has_declared_body and !finalized.contains(function.*))) {
                    ready = false;
                    break;
                }
            }
            if (!ready) continue;
            var nodes = unit.nodes.keyIterator();
            while (nodes.next()) |id| {
                if (graph.node(id.*).ty) |ty| if (graph.isTypeUnresolved(ty)) {
                    ready = false;
                    break;
                };
            }
            if (!ready) continue;
            try contracts.closeVirtualMethodRegistriesInUnit(&unit);
            try @import("../../execution/comptime.zig").resolveRequest(self.allocator, graph, diagnostics, node);
            const result = graph.node(node);
            const value: Value = switch (request.kind) {
                .boolean => if (result.content == .bool_literal) .{ .boolean = result.content.bool_literal } else {
                    self.functions.generics.comptime_failure = .{ .source = result.source, .reason = "compile-time condition requires a Bool result" };
                    return error.CompileTimeBooleanRequired;
                },
                .integer => blk: {
                    if (result.content != .int_literal) {
                        self.functions.generics.comptime_failure = .{ .source = result.source, .reason = "compile-time integer argument requires an integer result" };
                        return error.CompileTimeIntegerRequired;
                    }
                    const value = std.math.cast(i64, result.content.int_literal) orelse {
                        self.functions.generics.comptime_failure = .{ .source = result.source, .reason = "compile-time integer argument is outside the supported integer range" };
                        return error.ComptimeIntegerOverflow;
                    };
                    break :blk .{ .integer = value };
                },
            };
            try self.recordRequest(index);
            self.requests.items[index].value = value;
            changed = true;
        }
        return changed;
    }
};

test "staged integer requests retain bindings across pending retries" {
    const a = std.testing.allocator;
    var scheduler = Scheduler{ .allocator = a, .functions = undefined, .stable_type_count = 1 };
    defer scheduler.deinit();
    var bindings = try Generics.Bindings.init(a, 2);
    defer bindings.deinit(a);
    bindings.ints[0] = 6;
    bindings.types[1] = @enumFromInt(0);
    for (0..3) |_|
        try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.integer(&scheduler, 0, @enumFromInt(0), &bindings));
    try std.testing.expectEqual(@as(usize, 1), scheduler.requests.items.len);
    scheduler.requests.items[0].value = .{ .integer = 42 };
    try std.testing.expectEqual(@as(i64, 42), try Scheduler.integer(&scheduler, 0, @enumFromInt(0), &bindings));
    bindings.ints[0] = 7;
    try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.integer(&scheduler, 0, @enumFromInt(0), &bindings));
    try std.testing.expectEqual(@as(usize, 2), scheduler.requests.items.len);
}

test "staged request registration rolls back rejected selection demand" {
    const a = std.testing.allocator;
    var scheduler = Scheduler{ .allocator = a, .functions = undefined, .stable_type_count = 0 };
    defer scheduler.deinit();
    var bindings = try Generics.Bindings.init(a, 1);
    defer bindings.deinit(a);
    try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.integer(&scheduler, 0, @enumFromInt(0), &bindings));
    const saved = Scheduler.checkpoint(&scheduler);
    bindings.ints[0] = 5;
    try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.integer(&scheduler, 0, @enumFromInt(1), &bindings));
    Scheduler.rollback(&scheduler, saved);
    try std.testing.expectEqual(@as(usize, 1), scheduler.requests.items.len);
}

test "staged execution demand follows generic selection transactions" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    var core = @import("core.zig").Resolver{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    var generics = Generics{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer generics.deinit();
    var functions = Functions{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core, .generics = &generics };
    var scheduler = Scheduler{ .allocator = a, .functions = &functions, .stable_type_count = 0 };
    defer scheduler.deinit();
    generics.execution_context = &scheduler;
    generics.checkpoint_execution = Scheduler.checkpoint;
    generics.rollback_execution = Scheduler.rollback;
    var bindings = try Generics.Bindings.init(a, 0);
    defer bindings.deinit(a);
    {
        var selection = functions.beginSpeculation();
        defer selection.deinit();
        try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.integer(&scheduler, 0, @enumFromInt(0), &bindings));
    }
    try std.testing.expectEqual(@as(usize, 0), scheduler.requests.items.len);
    try std.testing.expect(!try scheduler.materialize());
    {
        var selection = functions.beginSpeculation();
        defer selection.deinit();
        try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.integer(&scheduler, 0, @enumFromInt(0), &bindings));
        selection.retainPendingExecution();
    }
    try std.testing.expectEqual(@as(usize, 1), scheduler.requests.items.len);
    {
        var outer = functions.beginSpeculation();
        defer outer.deinit();
        var inner = functions.beginSpeculation();
        defer inner.deinit();
        try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.integer(&scheduler, 0, @enumFromInt(1), &bindings));
        inner.retainPendingExecution();
    }
    try std.testing.expectEqual(@as(usize, 1), scheduler.requests.items.len);
    // The sole retained recipe belongs to the genuinely suspended selection.
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(scheduler.requests.items[0].expression));
}

test "staged conditions keep Bool results distinct from integer requests" {
    const a = std.testing.allocator;
    var scheduler = Scheduler{ .allocator = a, .functions = undefined, .stable_type_count = 0 };
    defer scheduler.deinit();
    var bindings = try Generics.Bindings.init(a, 0);
    defer bindings.deinit(a);
    try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.boolean(&scheduler, 0, @enumFromInt(0), &bindings));
    scheduler.requests.items[0].value = .{ .boolean = false };
    try std.testing.expectEqual(false, try Scheduler.boolean(&scheduler, 0, @enumFromInt(0), &bindings));
    try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.integer(&scheduler, 0, @enumFromInt(0), &bindings));
    try std.testing.expectEqual(@as(usize, 2), scheduler.requests.items.len);
}

fn cloneStagedRequests(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    var source: Scheduler = .{ .allocator = a, .functions = undefined, .stable_type_count = 4 };
    defer source.deinit();
    var bindings = try Generics.Bindings.init(a, 1);
    defer bindings.deinit(a);
    bindings.types[0] = @enumFromInt(2);
    bindings.ints[0] = 7;
    try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.integer(&source, 0, @enumFromInt(0), &bindings));
    source.requests.items[0].node = @enumFromInt(5);
    source.requests.items[0].value = .{ .integer = 42 };
    try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.boolean(&source, 0, @enumFromInt(1), &bindings));
    var functions: Functions = undefined;
    var candidate = try source.clone(allocator, &functions);
    defer candidate.deinit();
    try std.testing.expect(candidate.functions == &functions);
    try std.testing.expectEqual(@as(i64, 42), try Scheduler.integer(&candidate, 0, @enumFromInt(0), &bindings));
    try std.testing.expectEqual(@as(?g.GlobalNodeId, @enumFromInt(5)), candidate.requests.items[0].node);
    candidate.requests.items[1].bindings.ints[0] = 99;
    candidate.requests.items[1].bindings.types[0] = @enumFromInt(3);
    candidate.requests.items[1].value = .{ .boolean = true };
    try std.testing.expectEqual(@as(?i64, 7), source.requests.items[1].bindings.ints[0]);
    try std.testing.expectEqual(@as(?g.GlobalTypeId, @enumFromInt(2)), source.requests.items[1].bindings.types[0]);
    try std.testing.expectEqual(null, source.requests.items[1].value);
    Scheduler.rollback(&candidate, 1);
    try std.testing.expectEqual(@as(usize, 2), source.requests.items.len);
}

test "staged execution clones isolate recipes and retain frozen results" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneStagedRequests, .{});
}

test "staged requests own transient type descriptions after selection rollback" {
    for ([_]bool{ false, true }) |pending_errable| {
        const a = std.testing.allocator;
        var graph: g.GlobalSemanticGraph = .{};
        defer graph.deinit(a);
        try graph.types.append(a, .{ .builtin = .Int32 });
        var core = @import("core.zig").Resolver{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
        var generics = Generics{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
        defer generics.deinit();
        var functions = Functions{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core, .generics = &generics };
        var scheduler = Scheduler{ .allocator = a, .functions = &functions, .stable_type_count = 1 };
        defer scheduler.deinit();
        const checkpoint_ = graph.checkpoint();
        try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } });
        if (pending_errable) try graph.types.append(a, .{ .inferred_errable = .{ .child = @enumFromInt(1) } });
        var binding_types = [_]?g.GlobalTypeId{@enumFromInt(@as(u32, if (pending_errable) 2 else 1))};
        const bindings = Generics.Bindings{ .types = &binding_types, .ints = &.{} };
        try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.boolean(&scheduler, 0, @enumFromInt(0), &bindings));
        try std.testing.expectEqual(@as(usize, 1), scheduler.requests.items.len);
        try std.testing.expectEqual(null, scheduler.requests.items[0].bindings.types[0]);
        graph.rollback(a, checkpoint_);
        try graph.types.append(a, .{ .array = .{ .length = 2, .element = @enumFromInt(0) } });
        if (pending_errable) try graph.types.append(a, .{ .inferred_errable = .{ .child = @enumFromInt(1) } });
        try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.boolean(&scheduler, 0, @enumFromInt(0), &bindings));
        try std.testing.expectEqual(@as(usize, 2), scheduler.requests.items.len);
        graph.rollback(a, checkpoint_);
        try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } });
        if (pending_errable) try graph.types.append(a, .{ .inferred_errable = .{ .child = @enumFromInt(1) } });
        scheduler.requests.items[0].value = .{ .boolean = true };
        try std.testing.expect(try Scheduler.boolean(&scheduler, 0, @enumFromInt(0), &bindings));
    }
}

fn transientRequestFailures(a: std.mem.Allocator) !void {
    const graph_allocator = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(graph_allocator);
    try graph.types.append(graph_allocator, .{ .builtin = .Int32 });
    const source = @import("../primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.nodes.append(graph_allocator, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 42 } });
    try graph.fields.append(graph_allocator, .{ .name = try graph.addString(graph_allocator, "value"), .ty = @enumFromInt(0), .source = source, .default_value = @enumFromInt(0) });
    try graph.types.append(graph_allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } });
    var core = @import("core.zig").Resolver{ .allocator = graph_allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    var generics = Generics{ .allocator = graph_allocator, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer generics.deinit();
    var functions = Functions{ .allocator = graph_allocator, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core, .generics = &generics };
    var scheduler = Scheduler{ .allocator = a, .functions = &functions, .stable_type_count = 1 };
    defer scheduler.deinit();
    var types = [_]?g.GlobalTypeId{@enumFromInt(1)};
    const bindings = Generics.Bindings{ .types = &types, .ints = &.{} };
    _ = Scheduler.boolean(&scheduler, 0, @enumFromInt(0), &bindings) catch |err| switch (err) {
        error.ComptimeExecutionPending => false,
        else => return err,
    };
    var cloned = try scheduler.clone(a, &functions);
    defer cloned.deinit();
    cloned.requests.items[0].value = .{ .boolean = true };
    try std.testing.expect(try Scheduler.boolean(&cloned, 0, @enumFromInt(0), &bindings));
    Scheduler.rollback(&cloned, 0);
    try std.testing.expectEqual(@as(usize, 0), cloned.type_recipes.items.len);
    try std.testing.expectEqual(@as(usize, 1), scheduler.type_recipes.items.len);
}

test "staged transient requests release failed capture cloning and rollback" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, transientRequestFailures, .{});
}

test "staged request session rollback restores completed requests types and stable boundaries" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(a: std.mem.Allocator) !void {
            var scheduler: Scheduler = .{ .allocator = a, .functions = undefined, .stable_type_count = 1, .stable_declaration_count = 2, .stable_node_count = 3 };
            defer scheduler.deinit();
            var bindings = try Generics.Bindings.init(a, 1);
            defer bindings.deinit(a);
            try scheduler.enqueue(0, @enumFromInt(0), &bindings, .integer);
            scheduler.requests.items[0].types_published = false;
            const saved = scheduler.checkpointState();
            errdefer {
                scheduler.rollbackState(saved);
                std.debug.assert(std.meta.eql(saved, scheduler.checkpointState()));
                std.debug.assert(scheduler.requests.items[0].node == null and scheduler.requests.items[0].value == null);
                std.debug.assert(!scheduler.requests.items[0].types_published and scheduler.requests.items[0].bindings.types[0] == null);
            }
            try scheduler.recordRequest(0);
            scheduler.requests.items[0].types_published = true;
            scheduler.requests.items[0].bindings.types[0] = @enumFromInt(7);
            scheduler.requests.items[0].node = @enumFromInt(8);
            scheduler.requests.items[0].value = .{ .integer = 42 };
            scheduler.stable_type_count = 10;
            scheduler.stable_declaration_count = 11;
            scheduler.stable_node_count = 12;
            try scheduler.enqueue(0, @enumFromInt(1), &bindings, .boolean);
            scheduler.requests.items[1].node = @enumFromInt(9);
            scheduler.requests.items[1].value = .{ .boolean = true };
            var copy = try scheduler.clone(a, undefined);
            defer copy.deinit();
            copy.rollbackState(saved);
            scheduler.rollbackState(saved);
            try std.testing.expectEqualDeep(saved, scheduler.checkpointState());
            try std.testing.expectEqualDeep(saved, copy.checkpointState());
            try std.testing.expect(scheduler.requests.items[0].value == null);
            try std.testing.expect(copy.requests.items[0].bindings.types[0] == null);
        }
    }.run, .{});
}
