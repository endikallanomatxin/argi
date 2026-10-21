const std = @import("std");
const facts = @import("facts.zig");

// Copy immutable fact data into an owning publication arena. This copier is
// deliberately limited to fact records, scalar identities and their buffers;
// it cannot copy allocators, graph objects or arbitrary runtime pointers.
// Memoization preserves sharing and permits recursive ValueFacts references.
pub const Copy = struct {
    const Key = struct { address: usize, length: usize, kind: u64 };
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    seen: std.AutoHashMapUnmanaged(Key, usize) = .empty,

    pub fn deinit(self: *Copy) void {
        self.seen.deinit(self.scratch);
    }

    pub fn value(self: *Copy, comptime T: type, source: T) anyerror!T {
        return switch (@typeInfo(T)) {
            .void, .bool, .int, .float, .@"enum" => source,
            .optional => |optional| if (source) |item| try self.value(optional.child, item) else null,
            .@"struct" => |record| result: {
                var result: T = undefined;
                inline for (record.fields) |field| @field(result, field.name) = try self.value(field.type, @field(source, field.name));
                break :result result;
            },
            .@"union" => |choice| result: {
                if (choice.tag_type == null) @compileError("Fact snapshots require tagged unions");
                switch (source) {
                    inline else => |item, tag| break :result @unionInit(T, @tagName(tag), try self.value(@TypeOf(item), item)),
                }
            },
            .pointer => |pointer| result: {
                if (!pointer.is_const or pointer.sentinel() != null) @compileError("Fact snapshots accept immutable unsentinelized buffers only");
                if (pointer.size != .slice and !(pointer.size == .one and pointer.child == facts.ValueFacts))
                    @compileError("Unsupported pointer in published safety facts");
                const length = if (pointer.size == .slice) source.len else 1;
                if (length == 0) break :result &.{};
                const key: Key = .{ .address = @intFromPtr(if (pointer.size == .slice) source.ptr else source), .length = length, .kind = comptime std.hash.Wyhash.hash(0, @typeName(T)) };
                if (self.seen.get(key)) |address| {
                    if (pointer.size == .slice) break :result @as([*]const pointer.child, @ptrFromInt(address))[0..length];
                    break :result @as(T, @ptrFromInt(address));
                }
                if (pointer.size == .slice) {
                    const output = try self.allocator.alloc(pointer.child, length);
                    try self.seen.put(self.scratch, key, @intFromPtr(output.ptr));
                    for (source, output) |item, *out| out.* = try self.value(pointer.child, item);
                    break :result output;
                }
                const output = try self.allocator.create(pointer.child);
                try self.seen.put(self.scratch, key, @intFromPtr(output));
                output.* = try self.value(pointer.child, source.*);
                break :result output;
            },
            else => @compileError("Unsupported field in published safety facts"),
        };
    }
};

test "fact snapshots own shared values and projection buffers" {
    const a = std.testing.allocator;
    var publication = std.heap.ArenaAllocator.init(a);
    defer publication.deinit();
    var copy: Copy = .{ .allocator = publication.allocator(), .scratch = a };
    defer copy.deinit();
    var result: facts.ValueFacts = undefined;
    {
        var transient = std.heap.ArenaAllocator.init(a);
        defer transient.deinit();
        const paths = try transient.allocator().dupe(facts.Projection, &.{.{ .field = 3 }});
        const child = try transient.allocator().create(facts.ValueFacts);
        child.* = .{ .referenced_place = .{ .root = @enumFromInt(7), .projections = paths } };
        const fields = try transient.allocator().dupe(facts.FieldFacts, &.{ .{ .index = 0, .value = child }, .{ .index = 1, .value = child } });
        result = try copy.value(facts.ValueFacts, .{ .fields = fields });
        try std.testing.expect(result.fields.ptr != fields.ptr);
        try std.testing.expect(result.fields[0].value != child);
    }
    try std.testing.expect(result.fields[0].value == result.fields[1].value);
    try std.testing.expectEqual(@as(u32, 3), result.fields[0].value.referenced_place.?.projections[0].field);
}

fn copyFailures(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var copy: Copy = .{ .allocator = arena.allocator(), .scratch = a };
    defer copy.deinit();
    const shared: facts.ValueFacts = .{ .referenced_place = .{ .root = @enumFromInt(1), .projections = &.{.{ .field = 2 }} } };
    const source: facts.ValueFacts = .{ .fields = &.{ .{ .index = 0, .value = &shared }, .{ .index = 1, .value = &shared } } };
    const result = try copy.value(facts.ValueFacts, source);
    try std.testing.expect(result.fields[0].value == result.fields[1].value);
    try std.testing.expect(result.fields[0].value != &shared);
}

test "fact snapshots release all failed publication allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, copyFailures, .{});
}
