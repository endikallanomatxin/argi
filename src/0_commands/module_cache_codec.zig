const std = @import("std");
const graph_mod = @import("../4_semantics/module/graph.zig");
const verifier = @import("../4_semantics/module/complete_verify.zig");

pub const format_version: u32 = 9;
pub const max_file_bytes = 32 * 1024 * 1024;
const max_allocation_bytes = 64 * 1024 * 1024;
const magic = "ARGIMSG1";
const header_size = magic.len + 4 + 32 + 32;
const Hash = std.crypto.hash.Blake3;

/// The wire format contains fields and logical IDs, never pointer addresses,
/// allocator state, capacity, or padding. Compiler identity in the cache key
/// invalidates schema changes; the header independently versions this encoding.
pub fn encode(allocator: std.mem.Allocator, graph: *const graph_mod.ModuleSemanticGraph, fingerprint: [32]u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try output.appendSlice(allocator, magic);
    try appendInt(allocator, &output, format_version);
    try output.appendSlice(allocator, &fingerprint);
    try output.appendNTimes(allocator, 0, 32);
    try writeValue(allocator, &output, graph.*);
    if (output.items.len > max_file_bytes) return error.CacheTooLarge;
    Hash.hash(output.items[header_size..], output.items[header_size - 32 ..][0..32], .{});
    return output.toOwnedSlice(allocator);
}

pub fn decode(allocator: std.mem.Allocator, data: []const u8, fingerprint: [32]u8) !graph_mod.ModuleSemanticGraph {
    if (data.len < header_size or data.len > max_file_bytes) return error.InvalidCache;
    if (!std.mem.eql(u8, data[0..magic.len], magic)) return error.InvalidCache;
    if (std.mem.readInt(u32, data[magic.len..][0..4], .little) != format_version) return error.InvalidCache;
    if (!std.mem.eql(u8, data[magic.len + 4 ..][0..32], &fingerprint)) return error.InvalidCache;
    var checksum: [32]u8 = undefined;
    Hash.hash(data[header_size..], &checksum, .{});
    if (!std.mem.eql(u8, &checksum, data[header_size - 32 ..][0..32])) return error.InvalidCache;
    var reader = Reader{ .allocator = allocator, .bytes = data[header_size..] };
    const graph = try reader.readValue(graph_mod.ModuleSemanticGraph);
    if (reader.bytes.len != 0 or !graph.semantic.local_semantics_complete) return error.InvalidCache;
    try verifier.verifyModule(&graph);
    return graph;
}

inline fn appendInt(allocator: std.mem.Allocator, output: *std.ArrayList(u8), value: anytype) !void {
    const T = @TypeOf(value);
    const bits = @typeInfo(T).int.bits;
    const U = std.meta.Int(.unsigned, bits);
    const Wire = std.meta.Int(.unsigned, @max(8, ((bits + 7) / 8) * 8));
    var bytes: [@sizeOf(Wire)]u8 = undefined;
    std.mem.writeInt(Wire, &bytes, @as(U, @bitCast(value)), .little);
    try output.appendSlice(allocator, &bytes);
}

fn writeValue(allocator: std.mem.Allocator, output: *std.ArrayList(u8), value: anytype) error{ OutOfMemory, CacheTooLarge }!void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .void => {},
        .bool => try output.append(allocator, @intFromBool(value)),
        .int => try appendInt(allocator, output, value),
        .float => |info| try appendInt(allocator, output, @as(std.meta.Int(.unsigned, info.bits), @bitCast(value))),
        .@"enum" => try writeValue(allocator, output, @intFromEnum(value)),
        .optional => {
            try output.append(allocator, @intFromBool(value != null));
            if (value) |payload| try writeValue(allocator, output, payload);
        },
        .array => for (value) |item| try writeValue(allocator, output, item),
        .pointer => |info| {
            if (info.size != .slice or info.sentinel_ptr != null) @compileError("unsupported cache pointer: " ++ @typeName(T));
            if (value.len > std.math.maxInt(u32)) return error.CacheTooLarge;
            try appendInt(allocator, output, @as(u32, @intCast(value.len)));
            if (info.child == u8) {
                try output.appendSlice(allocator, value);
            } else for (value) |item| try writeValue(allocator, output, item);
        },
        .@"struct" => |info| {
            if (@hasField(T, "items") and @hasField(T, "capacity")) {
                try writeValue(allocator, output, value.items);
            } else inline for (info.fields) |field| try writeValue(allocator, output, @field(value, field.name));
        },
        .@"union" => |info| {
            if (info.tag_type == null) @compileError("cache requires tagged unions");
            inline for (info.fields, 0..) |field, index| {
                if (std.mem.eql(u8, @tagName(value), field.name)) {
                    try appendInt(allocator, output, @as(u32, @intCast(index)));
                    try writeValue(allocator, output, @field(value, field.name));
                    return;
                }
            }
            unreachable;
        },
        else => @compileError("unsupported cache type: " ++ @typeName(T)),
    }
    if (output.items.len > max_file_bytes) return error.CacheTooLarge;
}

const Reader = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,
    allocated_bytes: usize = 0,

    inline fn take(self: *Reader, count: usize) ![]const u8 {
        if (count > self.bytes.len) return error.InvalidCache;
        const bytes = self.bytes[0..count];
        self.bytes = self.bytes[count..];
        return bytes;
    }

    inline fn readInt(self: *Reader, comptime T: type) !T {
        const bits = @typeInfo(T).int.bits;
        const U = std.meta.Int(.unsigned, bits);
        const Wire = std.meta.Int(.unsigned, @max(8, ((bits + 7) / 8) * 8));
        const bytes = try self.take(@sizeOf(Wire));
        const value = std.mem.readInt(Wire, bytes[0..@sizeOf(Wire)], .little);
        if (value > std.math.maxInt(U)) return error.InvalidCache;
        return @bitCast(@as(U, @intCast(value)));
    }

    fn readValue(self: *Reader, comptime T: type) error{ OutOfMemory, InvalidCache }!T {
        switch (@typeInfo(T)) {
            .void => return {},
            .bool => return switch (try self.readInt(u8)) {
                0 => false,
                1 => true,
                else => error.InvalidCache,
            },
            .int => return self.readInt(T),
            .float => |info| return @bitCast(try self.readInt(std.meta.Int(.unsigned, info.bits))),
            .@"enum" => |info| {
                const value = try self.readInt(info.tag_type);
                if (!info.is_exhaustive) return @enumFromInt(value);
                return std.enums.fromInt(T, value) orelse error.InvalidCache;
            },
            .optional => |info| return if (try self.readValue(bool)) try self.readValue(info.child) else null,
            .array => |info| {
                var value: T = undefined;
                for (&value) |*item| item.* = try self.readValue(info.child);
                return value;
            },
            .pointer => |info| {
                if (info.size != .slice or info.sentinel_ptr != null) @compileError("unsupported cache pointer");
                const count = try self.readInt(u32);
                // Graph sequences have nonempty encodings. Bound allocation
                // before interpreting lengths or decoding their elements.
                if (count > self.bytes.len) return error.InvalidCache;
                const bytes = std.math.mul(usize, count, @sizeOf(info.child)) catch return error.InvalidCache;
                if (bytes > max_allocation_bytes - self.allocated_bytes) return error.InvalidCache;
                self.allocated_bytes += bytes;
                const value = try self.allocator.alloc(info.child, count);
                if (info.child == u8) {
                    @memcpy(value, try self.take(count));
                } else for (value) |*item| item.* = try self.readValue(info.child);
                return value;
            },
            .@"struct" => |info| {
                var value: T = undefined;
                if (@hasField(T, "items") and @hasField(T, "capacity")) {
                    value.items = try self.readValue(@TypeOf(value.items));
                    value.capacity = value.items.len;
                } else inline for (info.fields) |field| @field(value, field.name) = try self.readValue(field.type);
                return value;
            },
            .@"union" => |info| {
                const index = try self.readInt(u32);
                inline for (info.fields, 0..) |field, field_index| {
                    if (index == field_index) return @unionInit(T, field.name, try self.readValue(field.type));
                }
                return error.InvalidCache;
            },
            else => @compileError("unsupported cache type: " ++ @typeName(T)),
        }
    }
};

test "module cache codec rejects invalid lengths and scalar encodings" {
    var graph = graph_mod.ModuleSemanticGraph{ .module_dir = "empty" };
    graph.semantic.local_semantics_complete = true;
    const fingerprint: [32]u8 = @splat(7);
    const encoded = try encode(std.testing.allocator, &graph, fingerprint);
    defer std.testing.allocator.free(encoded);
    var target_bytes: std.ArrayList(u8) = .empty;
    defer target_bytes.deinit(std.testing.allocator);
    try writeValue(std.testing.allocator, &target_bytes, graph.target);
    const module_offset = header_size + target_bytes.items.len;
    for (0..3) |damage| {
        const data = try std.testing.allocator.dupe(u8, encoded);
        defer std.testing.allocator.free(data);
        if (damage == 0) {
            std.mem.writeInt(u32, data[module_offset..][0..4], std.math.maxInt(u32), .little);
        } else if (damage == 1) {
            data[module_offset + 4 + graph.module_dir.len] = 2;
        } else {
            data[header_size] = 255;
        }
        Hash.hash(data[header_size..], data[header_size - 32 ..][0..32], .{});
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(error.InvalidCache, decode(arena.allocator(), data, fingerprint));
    }
}
