const std = @import("std");
const value = @import("../5_codegen/bytecode/value.zig");
const Value = value.Value;
const Projection = value.Projection;
const Virtual = value.Virtual;

/// Nonmoving immutable payload allocations. Collection occurs only at a safe
/// point, after every allocated value and descriptor has been initialized.
pub const Heap = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayList(Block) = .empty,
    sorted: bool = true,
    head: ?usize = null,
    tail: ?usize = null,

    const Data = union(enum) {
        values: []Value,
        paths: []Projection,
        virtual: *Virtual,
    };
    const Block = struct {
        data: Data,
        marked: bool = false,
        next_mark: ?usize = null,
        pinned: bool = false,

        fn base(self: Block) usize {
            return switch (self.data) {
                .values => |items| @intFromPtr(items.ptr),
                .paths => |items| @intFromPtr(items.ptr),
                .virtual => |item| @intFromPtr(item),
            };
        }
        fn bytes(self: Block) usize {
            return switch (self.data) {
                .values => |items| items.len * @sizeOf(Value),
                .paths => |items| items.len * @sizeOf(Projection),
                .virtual => @sizeOf(Virtual),
            };
        }
        fn cells(self: Block) usize {
            return switch (self.data) {
                .values => |items| items.len,
                .paths => |items| items.len,
                .virtual => std.math.divCeil(usize, @sizeOf(Virtual), @sizeOf(Value)) catch unreachable,
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator) Heap {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Heap) void {
        for (self.blocks.items) |block| self.freeBlock(block);
        self.blocks.deinit(self.allocator);
        self.* = undefined;
    }
    fn reserve(self: *Heap) !void {
        try self.blocks.ensureUnusedCapacity(self.allocator, 1);
    }
    fn add(self: *Heap, data: Data, pinned: bool) void {
        self.blocks.appendAssumeCapacity(.{ .data = data, .pinned = pinned });
        self.sorted = false;
    }
    pub fn values(self: *Heap, count: usize, pinned: bool) ![]Value {
        if (count == 0) return &.{};
        try self.reserve();
        const items = try self.allocator.alloc(Value, count);
        @memset(items, .unit);
        self.add(.{ .values = items }, pinned);
        return items;
    }
    pub fn paths(self: *Heap, count: usize, pinned: bool) ![]Projection {
        if (count == 0) return &.{};
        try self.reserve();
        const items = try self.allocator.alloc(Projection, count);
        self.add(.{ .paths = items }, pinned);
        return items;
    }
    pub fn virtual(self: *Heap, pinned: bool) !*Virtual {
        try self.reserve();
        const item = try self.allocator.create(Virtual);
        self.add(.{ .virtual = item }, pinned);
        return item;
    }
    fn freeBlock(self: *Heap, block: Block) void {
        switch (block.data) {
            .values => |items| self.allocator.free(items),
            .paths => |items| self.allocator.free(items),
            .virtual => |item| self.allocator.destroy(item),
        }
    }
    fn freeAt(self: *Heap, address: usize) void {
        for (self.blocks.items, 0..) |block, index| {
            if (block.base() == address) {
                self.freeBlock(block);
                _ = self.blocks.swapRemove(index);
                self.sorted = false;
                return;
            }
        }
        unreachable;
    }
    pub fn freeValues(self: *Heap, items: []Value) void {
        if (items.len != 0) self.freeAt(@intFromPtr(items.ptr));
    }
    pub fn freePaths(self: *Heap, items: []Projection) void {
        if (items.len != 0) self.freeAt(@intFromPtr(items.ptr));
    }
    pub fn freeVirtual(self: *Heap, item: *Virtual) void {
        self.freeAt(@intFromPtr(item));
    }
    fn lessThan(_: void, a: Block, b: Block) bool {
        return a.base() < b.base();
    }
    fn lookup(self: *Heap, address: usize) ?usize {
        if (!self.sorted) {
            std.mem.sort(Block, self.blocks.items, {}, lessThan);
            self.sorted = true;
        }
        var low: usize = 0;
        var high = self.blocks.items.len;
        while (low < high) {
            const mid = low + (high - low) / 2;
            if (self.blocks.items[mid].base() <= address) low = mid + 1 else high = mid;
        }
        if (low == 0) return null;
        const index = low - 1;
        const block = self.blocks.items[index];
        return if (address - block.base() < block.bytes()) index else null;
    }
    fn ensureSorted(self: *Heap) void {
        if (!self.sorted) {
            std.mem.sort(Block, self.blocks.items, {}, lessThan);
            self.sorted = true;
        }
    }
    fn enqueue(self: *Heap, index: usize) void {
        const block = &self.blocks.items[index];
        if (block.marked) return;
        block.marked = true;
        block.next_mark = null;
        if (self.tail) |tail| {
            self.blocks.items[tail].next_mark = index;
        } else self.head = index;
        self.tail = index;
    }
    fn markAddress(self: *Heap, address: usize, pin: bool) bool {
        const index = self.lookup(address) orelse return false;
        if (pin) {
            self.blocks.items[index].pinned = true;
        } else self.enqueue(index);
        return true;
    }
    // Unowned wrapper arrays are traversed, but references do not follow their
    // target frames: those are roots independently maintained by the VM.
    fn markValue(self: *Heap, item: Value, pin: bool) void {
        switch (item) {
            .record, .array => |items| {
                if (items.len == 0) return;
                if (!self.markAddress(@intFromPtr(items.ptr), pin)) {
                    for (items) |child| self.markValue(child, pin);
                }
            },
            .choice => |choice| if (choice.payload) |payload| {
                if (!self.markAddress(@intFromPtr(payload), pin)) self.markValue(payload.*, pin);
            },
            .reference => |reference| if (reference.path.len != 0) {
                _ = self.markAddress(@intFromPtr(reference.path.ptr), pin);
            },
            .virtual_ => |descriptor| {
                if (!self.markAddress(@intFromPtr(descriptor), pin)) {
                    if (descriptor.receiver.path.len != 0) _ = self.markAddress(@intFromPtr(descriptor.receiver.path.ptr), pin);
                }
            },
            else => {},
        }
    }
    fn drain(self: *Heap) void {
        while (self.head) |index| {
            const block = self.blocks.items[index];
            self.head = block.next_mark;
            if (self.head == null) self.tail = null;
            self.blocks.items[index].next_mark = null;
            switch (block.data) {
                .values => |items| for (items) |item| self.markValue(item, false),
                .virtual => |descriptor| if (descriptor.receiver.path.len != 0) {
                    _ = self.markAddress(@intFromPtr(descriptor.receiver.path.ptr), false);
                },
                .paths => {},
            }
        }
    }
    pub fn publish(self: *Heap, item: Value) void {
        self.ensureSorted();
        self.markValue(item, true);
    }
    pub fn beginCollection(self: *Heap) void {
        self.ensureSorted();
        self.head = null;
        self.tail = null;
        for (self.blocks.items) |*block| {
            block.marked = false;
            block.next_mark = null;
        }
        for (0..self.blocks.items.len) |index| {
            if (self.blocks.items[index].pinned) self.enqueue(index);
        }
        self.drain();
    }
    pub fn mark(self: *Heap, item: Value) void {
        self.ensureSorted();
        self.markValue(item, false);
        self.drain();
    }
    pub fn sweep(self: *Heap) usize {
        var reclaimed: usize = 0;
        var kept: usize = 0;
        for (self.blocks.items) |block| {
            if (block.marked) {
                self.blocks.items[kept] = block;
                kept += 1;
            } else {
                reclaimed += block.cells();
                self.freeBlock(block);
            }
        }
        self.blocks.items.len = kept;
        return reclaimed;
    }
    pub fn retainedBytes(self: *const Heap) usize {
        var result = self.blocks.capacity * @sizeOf(Block);
        for (self.blocks.items) |block| result += block.bytes();
        return result;
    }
};

test "interior aggregate roots retain complete packed allocation" {
    var heap = Heap.init(std.testing.allocator);
    defer heap.deinit();
    const packed_values = try heap.values(3, false);
    packed_values[0] = .{ .integer = 1 };
    packed_values[1] = .{ .record = packed_values[2..3] };
    packed_values[2] = .{ .integer = 42 };
    _ = try heap.values(2, false);
    heap.beginCollection();
    heap.mark(.{ .record = packed_values[1..2] });
    try std.testing.expectEqual(@as(usize, 2), heap.sweep());
    try std.testing.expectEqual(@as(u64, 42), packed_values[1].record[0].integer);
    heap.beginCollection();
    try std.testing.expectEqual(@as(usize, 3), heap.sweep());
}

test "virtual receiver and public aggregate pin their paths" {
    var heap = Heap.init(std.testing.allocator);
    defer heap.deinit();
    const path = try heap.paths(1, false);
    path[0] = .{ .field = 7 };
    const descriptor = try heap.virtual(false);
    descriptor.receiver = .{ .context = @enumFromInt(0), .frame = @enumFromInt(0), .root = 0, .path = path, .mutability = .read_only };
    const record = try heap.values(1, false);
    record[0] = .{ .virtual_ = descriptor };
    heap.publish(.{ .record = record });
    heap.beginCollection();
    try std.testing.expectEqual(@as(usize, 0), heap.sweep());
    try std.testing.expectEqual(@as(u32, 7), record[0].virtual_.receiver.path[0].field);
}

test "failed heap allocations release all reservations" {
    const Probe = struct {
        fn run(a: std.mem.Allocator) !void {
            var heap = Heap.init(a);
            defer heap.deinit();
            const values_ = try heap.values(2, false);
            values_[0] = .unit;
            values_[1] = .unit;
            _ = try heap.paths(3, false);
            _ = try heap.virtual(false);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
