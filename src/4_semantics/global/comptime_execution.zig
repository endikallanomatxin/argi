const std = @import("std");
const g = @import("graph.zig");
const ir = @import("../module/parameterized/ir.zig");
const Generics = @import("generics.zig").Resolver;
const Functions = @import("generic_functions.zig").Resolver;
const reachability = @import("reachability.zig");

// Requests retain recipes independently of speculative graph tails. Only this
// coordinator publishes executable nodes, between ordinary resolution passes.
// Bound graph types must predate the current resolution pass before a recipe
// can retain their identities across a losing selection's rollback.
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    functions: *Functions,
    stable_type_count: usize,
    requests: std.ArrayList(Request) = .empty,

    const Request = struct {
        module: usize,
        expression: ir.ParameterizedNodeId,
        bindings: Generics.Bindings,
        node: ?g.GlobalNodeId = null,
        value: ?i64 = null,
    };

    pub fn deinit(self: *Scheduler) void {
        for (self.requests.items) |*request| request.bindings.deinit(self.allocator);
        self.requests.deinit(self.allocator);
    }

    pub fn checkpoint(context: *anyopaque) usize {
        const self: *Scheduler = @ptrCast(@alignCast(context));
        return self.requests.items.len;
    }

    pub fn rollback(context: *anyopaque, saved: usize) void {
        const self: *Scheduler = @ptrCast(@alignCast(context));
        for (self.requests.items[saved..]) |*request| {
            std.debug.assert(request.node == null);
            request.bindings.deinit(self.allocator);
        }
        self.requests.shrinkRetainingCapacity(saved);
    }

    pub fn integer(context: *anyopaque, module: usize, expression: ir.ParameterizedNodeId, bindings: *const Generics.Bindings) anyerror!i64 {
        const self: *Scheduler = @ptrCast(@alignCast(context));
        for (bindings.types) |ty| if (ty) |id| {
            if (@intFromEnum(id) >= self.stable_type_count) return error.ComptimeExecutionPending;
        };
        for (self.requests.items) |request| {
            if (request.module != module or request.expression != expression) continue;
            if (!equalBindings(request.bindings, bindings.*)) continue;
            return request.value orelse error.ComptimeExecutionPending;
        }
        try self.enqueue(module, expression, bindings);
        return error.ComptimeExecutionPending;
    }

    fn enqueue(self: *Scheduler, module: usize, expression: ir.ParameterizedNodeId, bindings: *const Generics.Bindings) !void {
        const types = try self.allocator.dupe(?g.GlobalTypeId, bindings.types);
        errdefer self.allocator.free(types);
        const ints = try self.allocator.dupe(?i64, bindings.ints);
        errdefer self.allocator.free(ints);
        try self.requests.append(self.allocator, .{ .module = module, .expression = expression, .bindings = .{ .types = types, .ints = ints } });
    }

    fn equalBindings(left: Generics.Bindings, right: Generics.Bindings) bool {
        if (left.ints.len != right.ints.len or left.types.len != right.types.len) return false;
        for (left.ints, right.ints) |a, b| if (a != b) return false;
        for (left.types, right.types) |a, b| if (a != b) return false;
        return true;
    }

    pub fn materialize(self: *Scheduler) !bool {
        var changed = false;
        const count = self.requests.items.len;
        for (0..count) |index| {
            // Instantiation can request other integers and grow this table.
            const request = self.requests.items[index];
            if (request.node != null) continue;
            var speculation = self.functions.beginSpeculation();
            defer speculation.deinit();
            var bindings = request.bindings;
            const node = self.functions.instantiateComptimeExpression(request.module, request.expression, &bindings) catch |err| switch (err) {
                error.ComptimeExecutionPending => {
                    speculation.retainPendingExecution();
                    continue;
                },
                error.UnboundComptimeParameter, error.UnboundGenericTypeParameter, error.UnresolvedParameterizedCall, error.UnresolvedParameterizedExpression => continue,
                else => return err,
            };
            try self.functions.graph.roots.append(self.allocator, node);
            self.requests.items[index].node = node;
            speculation.commit();
            changed = true;
        }
        return changed or self.requests.items.len != count;
    }

    pub fn evaluateReady(self: *Scheduler, diagnostics: *@import("../../1_base/diagnostic.zig").Diagnostics, finalized: *const std.AutoHashMap(g.GlobalFunctionId, void), pending_bodies: *const std.AutoHashMap(g.GlobalFunctionId, void)) !bool {
        var changed = false;
        const graph = self.functions.graph;
        for (self.requests.items) |*request| {
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
            try @import("../../execution/comptime.zig").resolveRequest(self.allocator, graph, diagnostics, node);
            const result = graph.node(node);
            if (result.content != .int_literal) {
                self.functions.generics.comptime_failure = .{ .source = result.source, .reason = "compile-time integer argument requires an integer result" };
                return error.CompileTimeIntegerRequired;
            }
            request.value = std.math.cast(i64, result.content.int_literal) orelse {
                self.functions.generics.comptime_failure = .{ .source = result.source, .reason = "compile-time integer argument is outside the supported integer range" };
                return error.ComptimeIntegerOverflow;
            };
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
    scheduler.requests.items[0].value = 42;
    try std.testing.expectEqual(@as(i64, 42), try Scheduler.integer(&scheduler, 0, @enumFromInt(0), &bindings));
    bindings.ints[0] = 7;
    try std.testing.expectError(error.ComptimeExecutionPending, Scheduler.integer(&scheduler, 0, @enumFromInt(0), &bindings));
    try std.testing.expectEqual(@as(usize, 2), scheduler.requests.items.len);
    bindings.types[1] = @enumFromInt(1);
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
    defer core.deinitReachedCalls();
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
