const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const Identity = @import("../../4_semantics/global/function_identity.zig").FunctionIdentity;
const b = @import("bytecode.zig");
const Proofs = @import("../../4_semantics/safety/body_cache.zig").Batch;

pub const ValidationKey = struct { unit: *const b.Program, function: g.GlobalFunctionId };

/// Indexes immutable verified bodies; the session owns their originating units.
/// Reserving may fail, but publication after semantic acceptance cannot allocate.
pub const Store = struct {
    const Entry = struct { identity: Identity, origin: *const b.Verified };
    const Work = struct { unit: *const b.Program, entry: b.FunctionEntry };
    allocator: std.mem.Allocator,
    entries: std.AutoHashMapUnmanaged(g.GlobalFunctionId, Entry) = .empty,

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Store) void {
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn lookup(self: *const Store, graph: *const g.GlobalSemanticGraph, id: g.GlobalFunctionId, session: ?b.Session) ?b.FunctionEntry {
        const entry = self.entries.get(id) orelse return null;
        const owner = entry.origin.program();
        if (owner.graph != graph or !entry.identity.matches(graph, id)) return null;
        if ((owner.session == null) != (session == null)) return null;
        if (session) |current| if (current.namespace != owner.session.?.namespace) return null;
        const original = owner.functionEntry(id).?;
        return .{ .id = id, .body = original.body, .origin = entry.origin, .safety_revision = original.safety_revision };
    }

    /// Validate the actual bytecode call closure, including helpers embedded in
    /// its origin unit. A caller's own summary can stay equal while a callee's
    /// proof changes. Never transplant the caller with that stale callee body.
    pub fn lookupChecked(self: *const Store, graph: *const g.GlobalSemanticGraph, id: g.GlobalFunctionId, session: ?b.Session, proofs: ?*const Proofs, scratch: std.mem.Allocator, validated: *std.AutoHashMapUnmanaged(ValidationKey, bool)) !?b.FunctionEntry {
        const entry = self.lookup(graph, id, session) orelse return null;
        const root: ValidationKey = .{ .unit = entry.origin.?.program(), .function = id };
        if (validated.get(root)) |valid| return if (valid) entry else null;
        var pending: std.ArrayList(Work) = .empty;
        defer pending.deinit(scratch);
        var visited: std.AutoHashMapUnmanaged(ValidationKey, void) = .empty;
        defer visited.deinit(scratch);
        try pending.append(scratch, .{ .unit = entry.origin.?.program(), .entry = entry });
        while (pending.pop()) |work| {
            const unit = if (work.entry.origin) |origin| origin.program() else work.unit;
            const key: ValidationKey = .{ .unit = unit, .function = work.entry.id };
            if (visited.contains(key)) continue;
            if (validated.get(key)) |valid| {
                if (!valid) {
                    try validated.put(scratch, root, false);
                    return null;
                }
                continue;
            }
            const wanted = proofRevision(graph, work.entry.id, proofs);
            if (wanted == null or wanted.? != work.entry.safety_revision) {
                try validated.put(scratch, root, false);
                return null;
            }
            try visited.put(scratch, key, {});
            try appendDependencies(&pending, scratch, unit, work.entry.body);
            // Module initializers can have ordinary calls and virtual tables.
            // Their selected methods retain the same proof requirements.
            for (unit.globals) |*global| try appendDependencies(&pending, scratch, unit, &global.initializer);
        }
        // Publish positive memo entries only after the whole closure succeeds.
        // Recursive SCCs cannot leave a prematurely accepted member behind.
        try validated.ensureUnusedCapacity(scratch, visited.count());
        var bodies = visited.keyIterator();
        while (bodies.next()) |body| validated.putAssumeCapacity(body.*, true);
        return entry;
    }

    fn appendDependencies(pending: *std.ArrayList(Work), allocator: std.mem.Allocator, unit: *const b.Program, body: *const b.Function) !void {
        for (body.code) |instruction| switch (instruction.op) {
            .call => |call| {
                const callee = unit.functionEntry(call.function) orelse return error.InvalidBytecode;
                try pending.append(allocator, .{ .unit = unit, .entry = callee });
            },
            .virtualize => |value| for (value.table.methods) |method| {
                const callee = unit.functionEntry(method.function) orelse return error.InvalidBytecode;
                try pending.append(allocator, .{ .unit = unit, .entry = callee });
            },
            else => {},
        };
    }

    pub fn reserve(self: *Store, program: b.Program) !void {
        var count: u32 = 0;
        for (program.functions) |entry| if (entry.origin == null) {
            count = try std.math.add(u32, count, 1);
        };
        try self.entries.ensureUnusedCapacity(self.allocator, count);
    }

    pub fn commit(self: *Store, origin: *const b.Verified, command: g.GlobalFunctionId) void {
        const program = origin.program();
        for (program.functions) |entry| {
            if (entry.safety_revision == std.math.maxInt(u64) or entry.origin != null or entry.id == command or program.graph.function(entry.id).flags.is_comptime_entry) continue;
            self.entries.putAssumeCapacity(entry.id, .{ .identity = Identity.read(program.graph, entry.id), .origin = origin });
        }
    }
};

/// Missing candidate proofs never fall back to an older accepted proof. Such a
/// body may have been rechecked without a reusable hypothesis closure.
pub fn proofRevision(graph: *const g.GlobalSemanticGraph, id: g.GlobalFunctionId, proofs: ?*const Proofs) ?u64 {
    const current = proofs orelse return 0;
    const function = graph.function(id);
    if (function.safety_primitive != .none or function.body == null) return 0;
    return current.revision(id);
}
