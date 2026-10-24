const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const Identity = @import("../../4_semantics/global/function_identity.zig").FunctionIdentity;
const b = @import("bytecode.zig");

/// Indexes immutable verified bodies; the session owns their originating units.
/// Reserving may fail, but publication after semantic acceptance cannot allocate.
pub const Store = struct {
    const Entry = struct { identity: Identity, origin: *const b.Verified };
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
        return .{ .id = id, .body = owner.function(id).?, .origin = entry.origin };
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
            if (entry.origin != null or entry.id == command or program.graph.function(entry.id).flags.is_comptime_entry) continue;
            self.entries.putAssumeCapacity(entry.id, .{ .identity = Identity.read(program.graph, entry.id), .origin = origin });
        }
    }
};
