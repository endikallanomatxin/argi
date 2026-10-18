const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const types = @import("../../4_semantics/global/types.zig");
const b = @import("bytecode.zig");
const Slot = b.Slot;
const Type = b.Type;
const Place = b.Place;
const Program = b.Program;
const Instruction = b.Instruction;
const supportedType = b.supportedType;
const valueFits = b.valueFits;
const integerBounds = b.integerBounds;
const choiceVariant = b.choiceVariant;

// Structural validation precedes dataflow: even unreachable instructions may
// never address invalid slots, call signatures or branch targets.
pub fn verify(allocator: std.mem.Allocator, program: Program) !void {
    if (!program.graph.target.isNative()) return error.UnsupportedExecutionTarget;
    if (program.functions.len != program.graph.functions.items.len) return error.InvalidBytecode;
    if (program.session) |session| {
        for (session.bindings, 0..) |binding, index| {
            if (@intFromEnum(binding.binding) >= program.graph.bindings.items.len or binding.slots.len == 0 or
                !types.equal(program.graph, binding.slots[0], program.graph.binding(binding.binding).ty)) return error.InvalidBytecode;
            for (session.bindings[0..index]) |previous| if (previous.binding == binding.binding) return error.InvalidBytecode;
            for (binding.slots) |ty| if (!supportedType(program.graph, ty, 0)) return error.InvalidBytecode;
            for (binding.slots[1..]) |ty| if (!valueFits(program.graph, ty, .{ .boolean = false })) return error.InvalidBytecode;
            for (binding.cleanup) |entry| if (entry.root != 0 or entry.flag == 0) return error.InvalidBytecode;
            try verifyCleanup(allocator, program.graph, .{ .slots = binding.slots, .inputs = &.{}, .outputs = &.{}, .code = &.{}, .cleanup = binding.cleanup });
        }
    }
    for (0..program.functions.len + @intFromBool(program.expression != null)) |fi| {
        const f = if (fi == program.functions.len) program.expression.?.* else program.functions[fi] orelse continue;
        if (f.code.len == 0) return error.InvalidBytecode;
        for (f.slots) |ty| if (!supportedType(program.graph, ty, 0)) return error.InvalidBytecode;
        for (f.write_destinations) |ty| if (!supportedType(program.graph, ty, 0)) return error.InvalidBytecode;
        for (f.inputs) |slot| if (slot >= f.slots.len) return error.InvalidBytecode;
        for (f.outputs) |slot| if (slot >= f.slots.len) return error.InvalidBytecode;
        if (fi < program.functions.len) {
            const declaration = program.graph.function(@enumFromInt(fi));
            if (f.inputs.len != declaration.input.len or f.outputs.len != declaration.output.len) return error.InvalidBytecode;
            for (f.inputs, 0..) |slot, i| if (slot >= f.slots.len or !types.equal(program.graph, f.slots[slot], program.graph.fields.items[declaration.input.start + i].ty)) return error.InvalidBytecode;
            for (f.outputs, 0..) |slot, i| if (slot >= f.slots.len or !types.equal(program.graph, f.slots[slot], program.graph.fields.items[declaration.output.start + i].ty)) return error.InvalidBytecode;
        }
        try verifyCleanup(allocator, program.graph, f);
        for (f.code) |inst| {
            var reads: std.ArrayList(Slot) = .empty;
            defer reads.deinit(allocator);
            var single: [1]Slot = undefined;
            for (destinations(inst, &single)) |dst| if (dst >= f.slots.len) return error.InvalidBytecode;
            try readSlots(allocator, inst, &reads);
            for (reads.items) |slot| if (slot >= f.slots.len) return error.InvalidBytecode;
            switch (inst.op) {
                .constant => |x| if (!valueFits(program.graph, f.slots[x.dst], x.value)) return error.InvalidBytecode,
                .trace_location => |x| {
                    if (!types.isBuiltin(program.graph, f.slots[x.dst], .UInt32) or x.location.line == 0 or x.location.column == 0) return error.InvalidBytecode;
                },
                .static_bytes => |x| {
                    const pointer = program.graph.semanticType(f.slots[x.dst]);
                    if (pointer != .pointer or pointer.pointer.mutability != .read_only or
                        !types.isBuiltin(program.graph, pointer.pointer.child, .UInt8)) return error.InvalidBytecode;
                },
                .offset_reference => |x| {
                    const pointer = program.graph.semanticType(f.slots[x.src]);
                    if (pointer != .pointer or !types.equal(program.graph, f.slots[x.dst], f.slots[x.src]) or
                        !types.isBuiltin(program.graph, f.slots[x.elements], .UIntNative)) return error.InvalidBytecode;
                },
                .virtualize => |x| {
                    const selected = x.table;
                    if (@intFromEnum(selected.virtual_type) >= program.graph.types.items.len or @intFromEnum(selected.concrete_type) >= program.graph.types.items.len or
                        program.graph.semanticType(selected.virtual_type) != .virtual or !types.equal(program.graph, f.slots[x.dst], selected.virtual_type)) return error.InvalidBytecode;
                    const receiver = program.graph.semanticType(f.slots[x.receiver]);
                    if (receiver != .pointer or !types.equal(program.graph, receiver.pointer.child, selected.concrete_type)) return error.InvalidBytecode;
                    for (selected.methods) |method| {
                        if (@intFromEnum(method.function) >= program.functions.len or program.functions[@intFromEnum(method.function)] == null) return error.InvalidBytecode;
                        const implementation = program.functions[@intFromEnum(method.function)].?;
                        if (method.receiver_input_index >= implementation.inputs.len) return error.InvalidBytecode;
                        const expected = program.graph.semanticType(implementation.slots[implementation.inputs[method.receiver_input_index]]);
                        if (expected != .pointer or !types.equal(program.graph, expected.pointer.child, selected.concrete_type) or
                            (expected.pointer.mutability == .read_write and receiver.pointer.mutability != .read_write)) return error.InvalidBytecode;
                    }
                },
                .virtual_call => |x| {
                    const signature = &x.signature;
                    if (x.args.len != signature.inputs.len or x.outputs.len != signature.outputs.len or signature.receiver_input_index >= x.args.len or signature.method_index >= signature.method_count) return error.InvalidBytecode;
                    if (@intFromEnum(signature.virtual_type) >= program.graph.types.items.len or program.graph.semanticType(signature.virtual_type) != .virtual) return error.InvalidBytecode;
                    const handle = program.graph.semanticType(f.slots[x.handle]);
                    if (handle != .pointer or !types.equal(program.graph, handle.pointer.child, signature.virtual_type) or
                        (signature.receiver_permission == .read_write and handle.pointer.mutability != .read_write)) return error.InvalidBytecode;
                    const contract = program.graph.semanticType(signature.virtual_type).virtual;
                    for (x.args, signature.inputs, 0..) |slot, ty, index| {
                        if (@intFromEnum(ty) >= program.graph.types.items.len) return error.InvalidBytecode;
                        if (index == signature.receiver_input_index) {
                            const receiver = program.graph.semanticType(ty);
                            if (slot != x.handle or receiver != .pointer or receiver.pointer.mutability != signature.receiver_permission or !types.equal(program.graph, receiver.pointer.child, contract)) return error.InvalidBytecode;
                        } else if (!types.equal(program.graph, f.slots[slot], ty)) return error.InvalidBytecode;
                    }
                    for (x.outputs, signature.outputs, 0..) |slot, ty, index| {
                        if (@intFromEnum(ty) >= program.graph.types.items.len or !types.equal(program.graph, f.slots[slot], ty)) return error.InvalidBytecode;
                        for (x.outputs[0..index]) |previous| if (previous == slot) return error.InvalidBytecode;
                    }
                },
                .copy => |x| if (!types.equal(program.graph, f.slots[x.dst], f.slots[x.src])) return error.InvalidBytecode,
                .session_initialize => |x| {
                    const binding = try sessionBinding(program, x.binding);
                    if (!types.equal(program.graph, binding.slots[0], f.slots[x.value])) return error.InvalidBytecode;
                },
                .session_borrow => |x| {
                    const binding = try sessionBinding(program, x.binding);
                    const pointer = program.graph.semanticType(f.slots[x.dst]);
                    if (pointer != .pointer or !types.equal(program.graph, binding.slots[0], pointer.pointer.child)) return error.InvalidBytecode;
                },
                .readonly => |x| {
                    const from = program.graph.semanticType(f.slots[x.src]);
                    const to = program.graph.semanticType(f.slots[x.dst]);
                    if (from != .pointer or to != .pointer or from.pointer.mutability != .read_write or to.pointer.mutability != .read_only or !types.equal(program.graph, from.pointer.child, to.pointer.child)) return error.InvalidBytecode;
                },
                .binary => |x| if (integerBounds(program.graph, f.slots[x.dst]) == null or !types.equal(program.graph, f.slots[x.dst], f.slots[x.left]) or !types.equal(program.graph, f.slots[x.left], f.slots[x.right])) return error.InvalidBytecode,
                .compare => |x| {
                    if (!valueFits(program.graph, f.slots[x.dst], .{ .boolean = false }) or !types.equal(program.graph, f.slots[x.left], f.slots[x.right])) return error.InvalidBytecode;
                    const integer = integerBounds(program.graph, f.slots[x.left]) != null;
                    const equality_only = valueFits(program.graph, f.slots[x.left], .{ .boolean = false }) or types.variants(program.graph, f.slots[x.left]) != null;
                    const equality = x.operator == .equal or x.operator == .not_equal;
                    if (!integer and !(equality_only and equality)) return error.InvalidBytecode;
                },
                .record => |x| {
                    const fields = types.fields(program.graph, f.slots[x.dst]) orelse return error.InvalidBytecode;
                    if (fields.len != x.fields.len) return error.InvalidBytecode;
                    for (x.fields, 0..) |slot, i| if (!types.equal(program.graph, f.slots[slot], program.graph.fields.items[fields.start + i].ty)) return error.InvalidBytecode;
                },
                .field => |x| {
                    const fields = types.fields(program.graph, f.slots[x.base]) orelse return error.InvalidBytecode;
                    if (x.index >= fields.len or !types.equal(program.graph, f.slots[x.dst], program.graph.fields.items[fields.start + x.index].ty)) return error.InvalidBytecode;
                },
                .array => |x| {
                    const element = types.arrayElement(program.graph, f.slots[x.dst]) orelse return error.InvalidBytecode;
                    if (types.arrayLength(program.graph, f.slots[x.dst]).? != x.elements.len) return error.InvalidBytecode;
                    for (x.elements) |slot| if (!types.equal(program.graph, f.slots[slot], element)) return error.InvalidBytecode;
                },
                .index => |x| {
                    const element = types.arrayElement(program.graph, f.slots[x.base]) orelse return error.InvalidBytecode;
                    if (!types.equal(program.graph, f.slots[x.dst], element) or integerBounds(program.graph, f.slots[x.index]) == null) return error.InvalidBytecode;
                },
                .choice => |x| {
                    const variant = try choiceVariant(program.graph, f.slots[x.dst], x.variant);
                    if (variant.payload_type) |payload_type| {
                        const payload = x.payload orelse return error.InvalidBytecode;
                        if (!types.equal(program.graph, f.slots[payload], payload_type)) return error.InvalidBytecode;
                    } else if (x.payload != null) return error.InvalidBytecode;
                },
                .payload => |x| {
                    const variant = try choiceVariant(program.graph, f.slots[x.src], x.variant);
                    if (!types.equal(program.graph, f.slots[x.dst], variant.payload_type orelse return error.InvalidBytecode)) return error.InvalidBytecode;
                },
                .is_variant => |x| {
                    _ = try choiceVariant(program.graph, f.slots[x.src], x.variant);
                    if (!valueFits(program.graph, f.slots[x.dst], .{ .boolean = false })) return error.InvalidBytecode;
                },
                .branch_variant => |x| {
                    _ = try choiceVariant(program.graph, f.slots[x.src], x.variant);
                    if (x.yes >= f.code.len or x.no >= f.code.len) return error.InvalidBytecode;
                },
                .borrow => |x| {
                    const target = try placeInfo(program, f.slots, x.place);
                    const pointer = program.graph.semanticType(f.slots[x.dst]);
                    if (pointer != .pointer or !types.equal(program.graph, pointer.pointer.child, target.ty) or (pointer.pointer.mutability == .read_write and !target.writable)) return error.InvalidBytecode;
                },
                .load => |x| {
                    const target = try placeInfo(program, f.slots, x.place);
                    if (!types.equal(program.graph, f.slots[x.dst], target.ty)) return error.InvalidBytecode;
                },
                .check_place => |place| _ = try placeInfo(program, f.slots, place),
                .capture_write => |x| {
                    if (x.dst >= f.write_destinations.len) return error.InvalidBytecode;
                    const target = try placeInfo(program, f.slots, x.place);
                    if (!target.writable or !types.equal(program.graph, f.write_destinations[x.dst], target.ty)) return error.InvalidBytecode;
                },
                .check_write_cleanup, .activate_write_cleanup => |destination| {
                    if (destination >= f.write_destinations.len) return error.InvalidBytecode;
                },
                .store => |x| {
                    if (x.destination >= f.write_destinations.len or !types.equal(program.graph, f.slots[x.value], f.write_destinations[x.destination])) return error.InvalidBytecode;
                },
                .cleanup_test => |x| {
                    _ = try placeInfo(program, f.slots, x.place);
                    if (!valueFits(program.graph, f.slots[x.dst], .{ .boolean = false })) return error.InvalidBytecode;
                },
                .cleanup_set => |x| {
                    if (!(try placeInfo(program, f.slots, x.place)).writable) return error.InvalidBytecode;
                },
                .branch => |x| if (x.yes >= f.code.len or x.no >= f.code.len or !valueFits(program.graph, f.slots[x.condition], .{ .boolean = false })) return error.InvalidBytecode,
                .jump => |target| if (target >= f.code.len) return error.InvalidBytecode,
                .ret => |slots| {
                    if (slots.len != f.outputs.len) return error.InvalidBytecode;
                    for (slots, f.outputs) |slot, output| if (!types.equal(program.graph, f.slots[slot], f.slots[output])) return error.InvalidBytecode;
                },
                .call => |x| {
                    if (@intFromEnum(x.function) >= program.functions.len) return error.InvalidBytecode;
                    const callee = program.functions[@intFromEnum(x.function)] orelse return error.InvalidBytecode;
                    if (x.args.len != callee.inputs.len or x.outputs.len != callee.outputs.len) return error.InvalidBytecode;
                    for (x.args, callee.inputs) |slot, input| if (!types.equal(program.graph, f.slots[slot], callee.slots[input])) return error.InvalidBytecode;
                    for (x.outputs, callee.outputs, 0..) |slot, output, index| {
                        if (!types.equal(program.graph, f.slots[slot], callee.slots[output])) return error.InvalidBytecode;
                        for (x.outputs[0..index]) |previous| if (previous == slot) return error.InvalidBytecode;
                    }
                },
                .abort_ => {},
            }
        }
        // Definite initialization is the intersection of every predecessor.
        const states = try allocator.alloc(?[]u8, f.code.len);
        defer {
            for (states) |s| if (s) |v| allocator.free(v);
            allocator.free(states);
        }
        // Abstract byte states: 0 unavailable, 1 initialized/captured,
        // 2 cleanup checked, 4 value written. Intersections preserve a stage
        // only when every incoming path establishes the same stage.
        @memset(states, null);
        states[0] = try allocator.alloc(u8, std.math.add(usize, f.slots.len, f.write_destinations.len) catch return error.InvalidBytecode);
        @memset(states[0].?, 0);
        for (f.inputs) |slot| states[0].?[slot] = 1;
        for (f.cleanup) |entry| states[0].?[entry.flag] = 1;
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(allocator);
        try pending.append(allocator, 0);
        while (pending.pop()) |pc| {
            const initialized = try allocator.dupe(u8, states[pc].?);
            defer allocator.free(initialized);
            var reads: std.ArrayList(Slot) = .empty;
            defer reads.deinit(allocator);
            const inst = f.code[pc];
            try readSlots(allocator, inst, &reads);
            for (reads.items) |slot| if (initialized[slot] == 0) return error.UninitializedBytecodeSlot;
            switch (inst.op) {
                .capture_write => |x| initialized[f.slots.len + x.dst] = 1,
                .check_write_cleanup => |id| {
                    const destination = f.slots.len + id;
                    if (initialized[destination] != 1) return error.UninitializedBytecodeDestination;
                    initialized[destination] = 2;
                },
                .store => |x| {
                    const destination = f.slots.len + x.destination;
                    if (initialized[destination] != 2) return error.UninitializedBytecodeDestination;
                    initialized[destination] = 4;
                },
                .activate_write_cleanup => |id| {
                    const destination = f.slots.len + id;
                    if (initialized[destination] != 4) return error.UninitializedBytecodeDestination;
                    initialized[destination] = 0;
                },
                else => {},
            }
            // Cleanup validation and publication enclose exactly one write.
            // No call, branch or retargeting may invalidate the checked state
            // between these three instructions.
            if (inst.op == .check_write_cleanup) {
                if (pc + 1 >= f.code.len or f.code[pc + 1].op != .store or
                    f.code[pc + 1].op.store.destination != inst.op.check_write_cleanup)
                    return error.UninitializedBytecodeDestination;
            }
            if (inst.op == .store) {
                if (pc + 1 >= f.code.len or f.code[pc + 1].op != .activate_write_cleanup or
                    f.code[pc + 1].op.activate_write_cleanup != inst.op.store.destination)
                    return error.UninitializedBytecodeDestination;
            }
            var single: [1]Slot = undefined;
            for (destinations(inst, &single)) |slot| initialized[slot] = 1;
            var successors: [2]u32 = undefined;
            const count: usize = switch (inst.op) {
                .ret, .abort_ => 0,
                .jump => |target| blk: {
                    successors[0] = target;
                    break :blk 1;
                },
                .branch_variant => |x| blk: {
                    successors = .{ x.yes, x.no };
                    break :blk 2;
                },
                .branch => |x| blk: {
                    successors = .{ x.yes, x.no };
                    break :blk 2;
                },
                else => blk: {
                    if (pc + 1 >= f.code.len) return error.InvalidBytecode;
                    successors[0] = pc + 1;
                    break :blk 1;
                },
            };
            for (successors[0..count]) |next| {
                var changed = false;
                if (states[next]) |old| {
                    for (old, initialized) |*was, now| if (was.* != (was.* & now)) {
                        was.* &= now;
                        changed = true;
                    };
                } else {
                    states[next] = try allocator.dupe(u8, initialized);
                    changed = true;
                }
                if (changed) try pending.append(allocator, next);
            }
        }
    }
}

fn destinations(i: Instruction, single: *[1]Slot) []const Slot {
    if (i.op == .call) return i.op.call.outputs;
    if (i.op == .virtual_call) return i.op.virtual_call.outputs;
    const slot: ?Slot = switch (i.op) {
        .constant => |x| x.dst,
        .static_bytes => |x| x.dst,
        .trace_location => |x| x.dst,
        .virtualize => |x| x.dst,
        .offset_reference => |x| x.dst,
        .copy => |x| x.dst,
        .session_borrow => |x| x.dst,
        .readonly => |x| x.dst,
        .binary => |x| x.dst,
        .compare => |x| x.dst,
        .record => |x| x.dst,
        .field => |x| x.dst,
        .array => |x| x.dst,
        .index => |x| x.dst,
        .choice => |x| x.dst,
        .payload => |x| x.dst,
        .is_variant => |x| x.dst,
        .borrow => |x| x.dst,
        .load => |x| x.dst,
        .cleanup_test => |x| x.dst,
        else => null,
    };
    if (slot) |value| {
        single[0] = value;
        return single;
    }
    return &.{};
}
fn readSlots(a: std.mem.Allocator, i: Instruction, out: *std.ArrayList(Slot)) !void {
    switch (i.op) {
        .copy => |x| try out.append(a, x.src),
        .virtualize => |x| try out.append(a, x.receiver),
        .virtual_call => |x| {
            try out.append(a, x.handle);
            try out.appendSlice(a, x.args);
        },
        .offset_reference => |x| try out.appendSlice(a, &.{ x.src, x.elements }),
        .session_initialize => |x| try out.append(a, x.value),
        .readonly => |x| try out.append(a, x.src),
        .binary => |x| try out.appendSlice(a, &.{ x.left, x.right }),
        .compare => |x| try out.appendSlice(a, &.{ x.left, x.right }),
        .record => |x| try out.appendSlice(a, x.fields),
        .field => |x| try out.append(a, x.base),
        .array => |x| try out.appendSlice(a, x.elements),
        .index => |x| try out.appendSlice(a, &.{ x.base, x.index }),
        .choice => |x| if (x.payload) |slot| try out.append(a, slot),
        .payload => |x| try out.append(a, x.src),
        .is_variant => |x| try out.append(a, x.src),
        .branch_variant => |x| try out.append(a, x.src),
        .borrow => |x| try readPlace(a, x.place, out),
        .load => |x| try readPlace(a, x.place, out),
        .check_place => |place| try readPlace(a, place, out),
        .capture_write => |x| try readPlace(a, x.place, out),
        .store => |x| try out.append(a, x.value),
        .cleanup_test => |x| try readCleanupPlace(a, x.place, out),
        .cleanup_set => |x| try readCleanupPlace(a, x.place, out),
        .call => |x| try out.appendSlice(a, x.args),
        .branch => |x| try out.append(a, x.condition),
        .ret => |x| try out.appendSlice(a, x),
        else => {},
    }
}

fn readCleanupPlace(a: std.mem.Allocator, place: Place, out: *std.ArrayList(Slot)) !void {
    // A static storage identity exists even before its value is initialized.
    // Following a runtime reference or index still requires initialized values.
    for (place.path) |projection| if (projection == .dereference or projection == .element) {
        return readPlace(a, place, out);
    };
}

fn verifyCleanup(a: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, f: b.Function) !void {
    const flags = try a.alloc(bool, f.slots.len);
    defer a.free(flags);
    @memset(flags, false);
    for (f.cleanup, 0..) |entry, index| {
        if (entry.root >= f.slots.len or entry.flag >= f.slots.len or flags[entry.flag] or
            entry.path.len > 64 or !valueFits(graph, f.slots[entry.flag], .{ .boolean = false })) return error.InvalidBytecode;
        flags[entry.flag] = true;
        var ty = f.slots[entry.root];
        for (entry.path) |projection| switch (projection) {
            .field => |field| {
                const fields = types.fields(graph, ty) orelse return error.InvalidBytecode;
                if (field >= fields.len) return error.InvalidBytecode;
                ty = graph.fields.items[fields.start + field].ty;
            },
            .variant => |id| ty = (try choiceVariant(graph, ty, @enumFromInt(id))).payload_type orelse return error.InvalidBytecode,
            .element => |element| {
                if (element >= (types.arrayLength(graph, ty) orelse return error.InvalidBytecode)) return error.InvalidBytecode;
                ty = types.arrayElement(graph, ty) orelse return error.InvalidBytecode;
            },
        };
        if (index != 0 and b.cleanupOrder(f.cleanup[index - 1], entry) != .lt) return error.InvalidBytecode;
    }
    for (f.cleanup) |entry| if (flags[entry.root]) return error.InvalidBytecode;
    for (f.inputs) |slot| if (flags[slot]) return error.InvalidBytecode;
    for (f.outputs) |slot| if (flags[slot]) return error.InvalidBytecode;
}

fn placeInfo(program: Program, slots: []const Type, place: Place) !struct { ty: Type, writable: bool } {
    const graph = program.graph;
    if (place.path.len > 64) return error.InvalidBytecode;
    var ty = if (place.region == .session)
        (try sessionBinding(program, place.root)).slots[0]
    else if (place.root < slots.len)
        slots[place.root]
    else
        return error.InvalidBytecode;
    var writable = true;
    for (place.path) |projection| switch (projection) {
        .field => |index| {
            const fields = types.fields(graph, ty) orelse return error.InvalidBytecode;
            if (index >= fields.len) return error.InvalidBytecode;
            ty = graph.fields.items[fields.start + index].ty;
        },
        .element => |index| {
            if (index >= slots.len or integerBounds(graph, slots[index]) == null) return error.InvalidBytecode;
            ty = types.arrayElement(graph, ty) orelse return error.InvalidBytecode;
        },
        .variant => |id| {
            const variant = try choiceVariant(graph, ty, id);
            ty = variant.payload_type orelse return error.InvalidBytecode;
        },
        .dereference => {
            const pointer = graph.semanticType(ty);
            if (pointer != .pointer) return error.InvalidBytecode;
            writable = pointer.pointer.mutability == .read_write;
            ty = pointer.pointer.child;
        },
    };
    return .{ .ty = ty, .writable = writable };
}

fn readPlace(a: std.mem.Allocator, place: Place, out: *std.ArrayList(Slot)) !void {
    if (place.region == .local) try out.append(a, place.root);
    for (place.path) |projection| switch (projection) {
        .element => |index| try out.append(a, index),
        .field, .variant, .dereference => {},
    };
}

fn sessionBinding(program: Program, index: u32) !b.SessionBinding {
    const session = program.session orelse return error.InvalidBytecode;
    if (index >= session.bindings.len) return error.InvalidBytecode;
    return session.bindings[index];
}
