const std = @import("std");
const storage_mod = @import("storage.zig");
const Storage = storage_mod.Storage;
const v = @import("../5_codegen/bytecode/value.zig");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const numeric = @import("../5_codegen/bytecode/numeric_layout.zig");
const partial = @import("partial_storage.zig");

fn setup(arena: std.mem.Allocator) !Storage {
    var storage = try Storage.init(arena, 4096);
    storage.bookkeeping_allocator = std.testing.allocator;
    storage.payloads = .init(std.testing.allocator);
    storage.executing = true;
    return storage;
}

test "live session partial values survive collection and dead frames do not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try setup(arena.allocator());
    defer storage.deinitBookkeeping();
    const session = try storage.enterSession(1, &.{});
    const layout: partial.Layout = .{ .nodes = &.{ .{ .kind = .record, .first = 1, .count = 2, .span = 3 }, .{ .offset = 1 }, .{ .offset = 2 } } };
    try storage.prepareStorage(session.frame, 0, layout);
    const nested = try storage.allocate(1);
    nested[0] = .{ .integer = 42 };
    const root: v.Reference = .{ .context = storage.context, .frame = session.frame, .root = 0, .path = &.{}, .mutability = .read_write };
    var first = root;
    first.path = &.{.{ .field = 0 }};
    try storage.store(first, .{ .array = nested });
    var second = root;
    second.path = &.{.{ .field = 1 }};
    try storage.store(second, .{ .integer = 9 });
    const dead = try storage.enter(1);
    const garbage = try storage.allocate(3);
    try (try storage.slots(dead)).put(0, .{ .array = garbage });
    storage.leave(dead);
    const before = storage.cells;
    storage.executing = false;
    storage.collectPayloads();
    try std.testing.expectEqual(before - 3, storage.cells);
    const observed = try storage.read(root);
    try std.testing.expectEqual(@as(u64, 42), observed.record[0].array[0].integer);
    try std.testing.expectError(error.ExecutionDeadReference, storage.read(.{ .context = storage.context, .frame = dead, .root = 0, .path = &.{}, .mutability = .read_only }));
}

test "external slot and reference reads retain packed snapshots after replacement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try setup(arena.allocator());
    defer storage.deinitBookkeeping();
    const session = try storage.enterSession(1, &.{});
    const source: v.Value = .{ .record = &.{.{ .array = &.{.{ .integer = 42 }} }} };
    try storage.initializeSession(session, 0, source);
    const root: v.Reference = .{ .context = storage.context, .frame = session.frame, .root = 0, .path = &.{}, .mutability = .read_write };
    storage.executing = false;
    const slot_snapshot = try session.get(0);
    const read_snapshot = try storage.read(root);
    storage.executing = true;
    try storage.reinitializeSession(session, 0, .{ .integer = 7 });
    storage.executing = false;
    storage.collectPayloads();
    try std.testing.expectEqual(@as(u64, 42), slot_snapshot.record[0].array[0].integer);
    try std.testing.expectEqual(@as(u64, 42), read_snapshot.record[0].array[0].integer);
    try std.testing.expectEqual(@as(u64, 7), (try storage.read(root)).integer);
}

test "acquired virtual evidence keeps its receiver projection after collection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try setup(arena.allocator());
    defer storage.deinitBookkeeping();
    const session = try storage.enterSession(1, &.{});
    try storage.initializeSession(session, 0, .{ .record = &.{.{ .integer = 42 }} });
    const receiver: v.Reference = .{ .context = storage.context, .frame = session.frame, .root = 0, .path = &.{.{ .field = 0 }}, .mutability = .read_only };
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    const program: b.Program = .{ .graph = &graph, .functions = &.{} };
    const table: b.VirtualTable = .{ .virtual_type = @enumFromInt(0), .concrete_type = @enumFromInt(0), .methods = &.{} };
    const value = try storage.virtualize(receiver, &program, &table);
    const physical: numeric.Layout = .{ .size = 16, .alignment = 8, .has_references = true, .shape = .virtual_reference };
    const logical: partial.Layout = .{ .nodes = &.{.{}} };
    const handle = try storage.acquisitions.acquire(&storage, 16, 8);
    const reservation = try storage.reserveAcquiredReceipt(handle, 0, &physical, .little, logical, null, 1, 0);
    const slot = try storage.borrowAcquiredElement(reservation, 0, .read_write);
    try storage.store(slot, value);
    storage.executing = false;
    storage.collectPayloads();
    const retained = try storage.read(slot);
    try std.testing.expectEqual(@as(u64, 42), (try storage.read(retained.virtual_.receiver)).integer);
    try std.testing.expect(retained.virtual_.table == &table);
}

test "repeated partial materialization reclaims superseded snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try setup(arena.allocator());
    defer storage.deinitBookkeeping();
    const session = try storage.enterSession(1, &.{});
    const layout: partial.Layout = .{ .nodes = &.{ .{ .kind = .record, .first = 1, .count = 2, .span = 3 }, .{ .offset = 1 }, .{ .offset = 2 } } };
    try storage.prepareStorage(session.frame, 0, layout);
    const root: v.Reference = .{ .context = storage.context, .frame = session.frame, .root = 0, .path = &.{}, .mutability = .read_write };
    var first = root;
    first.path = &.{.{ .field = 0 }};
    var second = root;
    second.path = &.{.{ .field = 1 }};
    try storage.store(second, .{ .integer = 7 });
    for (0..100) |index| {
        storage.executing = true;
        try storage.store(first, .{ .integer = @intCast(index) });
        const observed = try storage.read(root);
        try std.testing.expectEqual(@as(u64, @intCast(index)), observed.record[0].integer);
        storage.executing = false;
        storage.collectPayloads();
    }
    try std.testing.expect(storage.cells <= 8);
}

test "released acquired storage does not root obsolete virtual evidence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try setup(arena.allocator());
    defer storage.deinitBookkeeping();
    const session = try storage.enterSession(1, &.{});
    try storage.initializeSession(session, 0, .{ .record = &.{.{ .integer = 42 }} });
    const receiver: v.Reference = .{ .context = storage.context, .frame = session.frame, .root = 0, .path = &.{.{ .field = 0 }}, .mutability = .read_only };
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    const program: b.Program = .{ .graph = &graph, .functions = &.{} };
    const table: b.VirtualTable = .{ .virtual_type = @enumFromInt(0), .concrete_type = @enumFromInt(0), .methods = &.{} };
    const value = try storage.virtualize(receiver, &program, &table);
    const physical: numeric.Layout = .{ .size = 16, .alignment = 8, .has_references = true, .shape = .virtual_reference };
    const logical: partial.Layout = .{ .nodes = &.{.{}} };
    const handle = try storage.acquisitions.acquire(&storage, 16, 8);
    const reservation = try storage.reserveAcquiredReceipt(handle, 0, &physical, .little, logical, null, 1, 0);
    const slot = try storage.borrowAcquiredElement(reservation, 0, .read_write);
    try storage.store(slot, value);
    storage.executing = false;
    storage.collectPayloads();
    const before = storage.cells;
    try storage.acquisitions.release(&storage, handle);
    storage.collectPayloads();
    const virtual_cells = std.math.divCeil(usize, @sizeOf(v.Virtual), @sizeOf(v.Value)) catch unreachable;
    try std.testing.expectEqual(before - virtual_cells - 1, storage.cells);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.read(slot));
}
