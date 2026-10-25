const std = @import("std");
const sema = @import("semantizer.zig");

/// Resolve module conditions to a fixed point in one mutable semantic candidate.
/// The source owner materializes selected fragments and newly discovered imports;
/// neither the scheduler nor the source owner publishes the candidate here.
/// Earlier accepted modules already have fixed choices and are never revisited.
pub fn resolve(allocator: std.mem.Allocator, session: *sema.Session, first_module: usize, loader: anytype) !void {
    var completed: std.AutoHashMapUnmanaged(u64, void) = .empty;
    defer completed.deinit(allocator);
    while (true) {
        var changed = false;
        const count = session.modules.len;
        for (first_module..count) |module_index| {
            // Loading a selected import can relocate the module view table.
            const module = session.modules[module_index];
            for (module.conditions.items, 0..) |condition, index| {
                const key = (@as(u64, @intCast(module_index)) << 32) | @as(u32, @intCast(index));
                if (completed.contains(key)) continue;
                const decision = try session.evaluateModuleCondition(module_index, condition.expression) orelse continue;
                try loader.materialize(session, module_index, condition, decision);
                try completed.put(allocator, key, {});
                changed = true;
            }
        }
        if (!changed) break;
    }
    if (try @import("module_linker.zig").cycleSource(allocator, &session.relocation.graph)) |source| {
        const diagnostics = session.options.diagnostics orelse return error.MissingCompileTimeDiagnostics;
        try diagnostics.add(@import("source_location.zig").location(&session.relocation.graph, diagnostics, source), .semantic, "import cycle detected after compile-time selection", .{});
        return error.Reported;
    }
}
