const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const g = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");

// External arguments are copied representations, never executor references.
// Resolve their bounded representation once at VM preparation, keeping semantic
// graph traversal out of invocation and ordinary instruction execution.
pub const Shape = union(enum) {
    forbidden,
    integer: u64,
    float16,
    float32,
    float64,
    boolean,
    unit,
    erased,
    record: []const *const Shape,
    array: struct { element: *const Shape, length: usize },
    choice: []const ?*const Shape,

    pub fn accepts(self: *const Shape, value: b.Value) bool {
        return switch (self.*) {
            .forbidden => false,
            .integer => |maximum| value == .integer and value.integer <= maximum,
            .float16 => value == .float16,
            .float32 => value == .float32,
            .float64 => value == .float64,
            .boolean => value == .boolean,
            .unit => value == .unit,
            .erased => value == .erased,
            .record => |fields| blk: {
                if (value != .record or fields.len != value.record.len) break :blk false;
                for (fields, value.record) |field, item| if (!field.accepts(item)) break :blk false;
                break :blk true;
            },
            .array => |array| blk: {
                if (value != .array or value.array.len != array.length) break :blk false;
                for (value.array) |item| if (!array.element.accepts(item)) break :blk false;
                break :blk true;
            },
            .choice => |variants| blk: {
                if (value != .choice or value.choice.variant >= variants.len) break :blk false;
                if (variants[value.choice.variant]) |payload|
                    break :blk if (value.choice.payload) |item| payload.accepts(item.*) else false;
                break :blk value.choice.payload == null;
            },
        };
    }
};

pub const Inputs = struct {
    arena: std.heap.ArenaAllocator,
    functions: std.AutoHashMapUnmanaged(*const b.Function, []const *const Shape) = .empty,

    pub fn init(allocator: std.mem.Allocator, program: b.Program) !Inputs {
        var result: Inputs = .{ .arena = .init(allocator) };
        errdefer result.deinit();
        var compiler: Compiler = .{ .allocator = result.arena.allocator(), .graph = program.graph };
        for (program.functions) |function| if (function) |body| try result.add(&compiler, body);
        if (program.expression) |body| try result.add(&compiler, body);
        return result;
    }

    fn add(self: *Inputs, compiler: *Compiler, function: *const b.Function) !void {
        // Commands and cleanup entries normally have no external inputs. Their
        // arity is already explicit: no descriptor or hash entry is needed.
        if (function.inputs.len == 0) return;
        if (self.functions.contains(function)) return;
        const shapes = try compiler.allocator.alloc(*const Shape, function.inputs.len);
        for (shapes, function.inputs) |*shape, slot| shape.* = try compiler.compile(function.slots[slot], 0);
        try self.functions.put(compiler.allocator, function, shapes);
    }

    pub fn deinit(self: *Inputs) void {
        self.arena.deinit();
    }

    pub fn accepts(self: *const Inputs, function: *const b.Function, values: []const b.Value) bool {
        if (function.inputs.len == 0) return values.len == 0;
        const shapes = self.functions.get(function) orelse return false;
        if (shapes.len != values.len) return false;
        for (shapes, values) |shape, value| if (!shape.accepts(value)) return false;
        return true;
    }
};

const Compiler = struct {
    allocator: std.mem.Allocator,
    graph: *const g.GlobalSemanticGraph,
    cache: std.AutoHashMapUnmanaged(b.Type, *const Shape) = .empty,

    fn compile(self: *Compiler, ty: b.Type, depth: usize) anyerror!*const Shape {
        if (self.cache.get(ty)) |shape| return shape;
        const result = try self.allocator.create(Shape);
        result.* = .forbidden;
        // Insert before recursion: recursive value shapes terminate at references,
        // which are forbidden at this external boundary.
        try self.cache.put(self.allocator, ty, result);
        if (depth > 64) return result;
        if (b.integerBounds(self.graph, ty)) |bounds| {
            result.* = .{ .integer = @intCast(bounds.maximum - bounds.minimum) };
        } else if (types.isBuiltin(self.graph, ty, .Float16)) {
            result.* = .float16;
        } else if (types.isBuiltin(self.graph, ty, .Float32)) {
            result.* = .float32;
        } else if (types.isBuiltin(self.graph, ty, .Float64)) {
            result.* = .float64;
        } else if (types.isBuiltin(self.graph, ty, .Bool)) {
            result.* = .boolean;
        } else if (types.isBuiltin(self.graph, ty, .Void)) {
            result.* = .unit;
        } else if (types.isBuiltin(self.graph, ty, .Any)) {
            result.* = .erased;
        } else if (types.arrayElement(self.graph, ty)) |element| {
            result.* = .{ .array = .{ .element = try self.compile(element, depth + 1), .length = @intCast(types.arrayLength(self.graph, ty).?) } };
        } else if (types.variants(self.graph, ty)) |variants| {
            const shapes = try self.allocator.alloc(?*const Shape, variants.len);
            for (shapes, self.graph.variants.items[variants.start..][0..variants.len]) |*shape, variant|
                shape.* = if (variant.payload_type) |payload| try self.compile(payload, depth + 1) else null;
            result.* = .{ .choice = shapes };
        } else if (types.fields(self.graph, ty)) |fields| {
            const shapes = try self.allocator.alloc(*const Shape, fields.len);
            for (shapes, self.graph.fields.items[fields.start..][0..fields.len]) |*shape, field| shape.* = try self.compile(field.ty, depth + 1);
            result.* = .{ .record = shapes };
        }
        return result;
    }
};

fn prepareInputs(allocator: std.mem.Allocator) !void {
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .Int8 },
        .{ .array = .{ .element = @enumFromInt(0), .length = 2 } },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
    });
    const function: b.Function = .{ .slots = &.{@enumFromInt(1)}, .inputs = &.{0}, .outputs = &.{}, .code = &.{} };
    const pointer_function: b.Function = .{ .slots = &.{@enumFromInt(2)}, .inputs = &.{0}, .outputs = &.{}, .code = &.{} };
    var inputs = try Inputs.init(allocator, .{ .graph = &graph, .functions = &.{ &function, &pointer_function } });
    defer inputs.deinit();
    const valid: b.Value = .{ .array = &.{ .{ .integer = 128 }, .{ .integer = 255 } } };
    try std.testing.expect(inputs.accepts(&function, &.{valid}));
    try std.testing.expect(!inputs.accepts(&function, &.{.{ .array = &.{ .{ .integer = 256 }, .{ .integer = 0 } } }}));
    try std.testing.expect(!inputs.accepts(&function, &.{.{ .array = &.{.{ .integer = 0 }} }}));
    try std.testing.expect(!inputs.accepts(&pointer_function, &.{.{ .reference = .{ .context = @enumFromInt(0), .frame = @enumFromInt(0), .root = 0, .path = &.{}, .mutability = .read_write } }}));
    // Invocation consumes only prepared shape metadata, even if the semantic
    // type table is no longer available to describe its original input.
    graph.types.clearRetainingCapacity();
    try std.testing.expect(inputs.accepts(&function, &.{valid}));
}

test "prepared input layouts preserve widths and reject external references" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, prepareInputs, .{});
}

test "input-free execution entries need no descriptor allocations" {
    var graph: g.GlobalSemanticGraph = .{};
    const function: b.Function = .{ .slots = &.{}, .inputs = &.{}, .outputs = &.{}, .code = &.{} };
    var empty: [0]u8 = .{};
    var backing = std.heap.FixedBufferAllocator.init(&empty);
    var inputs = try Inputs.init(backing.allocator(), .{ .graph = &graph, .functions = &.{&function}, .expression = &function });
    defer inputs.deinit();
    try std.testing.expectEqual(@as(usize, 0), inputs.functions.count());
    try std.testing.expect(inputs.accepts(&function, &.{}));
    try std.testing.expect(!inputs.accepts(&function, &.{.{ .integer = 0 }}));
}
