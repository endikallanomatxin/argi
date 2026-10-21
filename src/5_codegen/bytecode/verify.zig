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
    const owning_types = try @import("../cleanup_layout.zig").owningTypes(allocator, program.graph);
    defer allocator.free(owning_types);
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
    for (program.host_functions, 0..) |function, index| {
        if (!@import("host_signature.zig").matches(program.graph, function)) return error.InvalidBytecode;
        for (program.host_functions[0..index]) |previous| if (previous.function == function.function) return error.InvalidBytecode;
    }
    const module_bindings = try allocator.alloc(bool, program.graph.bindings.items.len);
    defer allocator.free(module_bindings);
    @memset(module_bindings, false);
    for (program.graph.roots.items) |root| {
        const node = program.graph.node(root);
        if (node.content == .binding_declaration) module_bindings[@intFromEnum(node.content.binding_declaration)] = true;
    }
    for (program.globals, 0..) |global, index| {
        if (@intFromEnum(global.binding) >= program.graph.bindings.items.len or !module_bindings[@intFromEnum(global.binding)] or !types.equal(program.graph, global.ty, program.graph.binding(global.binding).ty)) return error.InvalidBytecode;
        for (program.globals[0..index]) |previous| if (previous.binding == global.binding) return error.InvalidBytecode;
        if (global.initializer.inputs.len != 0 or global.initializer.outputs.len != 1) return error.InvalidBytecode;
        const output = global.initializer.outputs[0];
        if (output >= global.initializer.slots.len or !types.equal(program.graph, global.initializer.slots[output], global.ty)) return error.InvalidBytecode;
    }
    const expression_end = program.functions.len + @intFromBool(program.expression != null);
    for (0..expression_end + program.globals.len) |fi| {
        const f = if (fi >= expression_end) program.globals[fi - expression_end].initializer else if (fi == program.functions.len) program.expression.?.* else program.functions[fi] orelse continue;
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
                .reserve_storage => |x| {
                    const expected = try @import("storage_layout.zig").compile(allocator, program.graph, f.slots[x.dst]);
                    defer allocator.free(expected.nodes);
                    if (expected.nodes.len != x.layout.nodes.len) return error.InvalidBytecode;
                    for (expected.nodes, x.layout.nodes) |wanted, actual| if (!std.meta.eql(wanted, actual)) return error.InvalidBytecode;
                },
                .constant => |x| if (!valueFits(program.graph, f.slots[x.dst], x.value)) return error.InvalidBytecode,
                .resolve_location => |x| {
                    if (!types.isBuiltin(program.graph, f.slots[x.id], .UInt32)) return error.InvalidBytecode;
                    const fields = types.fields(program.graph, f.slots[x.dst]) orelse return error.InvalidBytecode;
                    if (fields.len != 4) return error.InvalidBytecode;
                    const names = [_][]const u8{ "source_file", "source_line", "line", "column" };
                    for (program.graph.fields.items[fields.start..][0..fields.len], 0..) |field, index| {
                        if (!std.mem.eql(u8, program.graph.text(field.name), names[index])) return error.InvalidBytecode;
                        if (index < 2) {
                            const pointer = program.graph.semanticType(field.ty);
                            if (pointer != .pointer or pointer.pointer.mutability != .read_only) return error.InvalidBytecode;
                            const bounds = integerBounds(program.graph, pointer.pointer.child) orelse return error.InvalidBytecode;
                            if (bounds.maximum - bounds.minimum != 255) return error.InvalidBytecode;
                        } else if (!types.isBuiltin(program.graph, field.ty, .UIntNative)) return error.InvalidBytecode;
                    }
                },
                .trace_location => |x| {
                    if (!types.isBuiltin(program.graph, f.slots[x.dst], .UInt32) or x.location.line == 0 or x.location.column == 0) return error.InvalidBytecode;
                },
                .static_bytes => |x| {
                    const pointer = program.graph.semanticType(f.slots[x.dst]);
                    if (pointer != .pointer or pointer.pointer.mutability != .read_only) return error.InvalidBytecode;
                    const bounds = integerBounds(program.graph, pointer.pointer.child) orelse return error.InvalidBytecode;
                    if (bounds.maximum - bounds.minimum != 255) return error.InvalidBytecode;
                },
                .acquired_reference => |x| {
                    if (fi >= program.graph.functions.items.len) return error.InvalidBytecode;
                    const primitive = program.graph.function(@enumFromInt(@as(u32, @intCast(fi)))).safety_primitive;
                    if (primitive != .establish_inherited_reference and primitive != .establish_allocation_slot) return error.InvalidBytecode;
                    const target = program.graph.semanticType(f.slots[x.dst]);
                    if (target != .pointer or !types.isBuiltin(program.graph, f.slots[x.address], .UIntNative)) return error.InvalidBytecode;
                    var arena = std.heap.ArenaAllocator.init(allocator);
                    defer arena.deinit();
                    if (x.permission != target.pointer.mutability or x.endian != program.graph.target.stdTarget().cpu.arch.endian()) return error.InvalidBytecode;
                    if (owning_types[@intFromEnum(target.pointer.child)]) return error.InvalidBytecode;
                    const expected = @import("numeric_layout.zig").compile(arena.allocator(), program.graph, target.pointer.child) catch return error.InvalidBytecode;
                    if (!@import("numeric_layout.zig").equal(expected, x.layout)) return error.InvalidBytecode;
                },
                .erase_reference => |x| {
                    const from = program.graph.semanticType(f.slots[x.src]);
                    const to = program.graph.semanticType(f.slots[x.dst]);
                    if (from != .pointer or to != .pointer or to.pointer.mutability != .read_only or !types.isBuiltin(program.graph, to.pointer.child, .Any)) return error.InvalidBytecode;
                },
                .numeric_bytes => |x| {
                    const from = program.graph.semanticType(f.slots[x.src]);
                    const to = program.graph.semanticType(f.slots[x.dst]);
                    if (from != .pointer or to != .pointer or !types.isBuiltin(program.graph, to.pointer.child, .UInt8) or
                        (to.pointer.mutability == .read_write and from.pointer.mutability != .read_write)) return error.InvalidBytecode;
                    if (x.permission != to.pointer.mutability or x.endian != program.graph.target.arch.endian()) return error.InvalidBytecode;
                    var arena = std.heap.ArenaAllocator.init(allocator);
                    defer arena.deinit();
                    const expected = @import("numeric_layout.zig").compile(arena.allocator(), program.graph, from.pointer.child) catch return error.InvalidBytecode;
                    if (!@import("numeric_layout.zig").equal(expected, x.layout)) return error.InvalidBytecode;
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
                .session_declare => |x| {
                    const binding = try sessionBinding(program, x.binding);
                    if (x.layout) |layout| {
                        const expected = try @import("storage_layout.zig").compile(allocator, program.graph, binding.slots[0]);
                        defer allocator.free(expected.nodes);
                        if (expected.nodes.len != layout.nodes.len) return error.InvalidBytecode;
                        for (expected.nodes, layout.nodes) |wanted, actual| if (!std.meta.eql(wanted, actual)) return error.InvalidBytecode;
                    }
                },
                .session_initialize => |x| {
                    const binding = try sessionBinding(program, x.binding);
                    if (!types.equal(program.graph, binding.slots[0], f.slots[x.value])) return error.InvalidBytecode;
                },
                .readonly => |x| {
                    const from = program.graph.semanticType(f.slots[x.src]);
                    const to = program.graph.semanticType(f.slots[x.dst]);
                    if (from != .pointer or to != .pointer or from.pointer.mutability != .read_write or to.pointer.mutability != .read_only or !types.equal(program.graph, from.pointer.child, to.pointer.child)) return error.InvalidBytecode;
                },
                .binary => |x| {
                    if (x.kind != b.scalarKind(program.graph, f.slots[x.dst]) or (x.kind.bounds() == null and !x.kind.floating()) or !types.equal(program.graph, f.slots[x.dst], f.slots[x.left]) or !types.equal(program.graph, f.slots[x.left], f.slots[x.right])) return error.InvalidBytecode;
                },
                .compare => |x| {
                    if (x.kind != b.scalarKind(program.graph, f.slots[x.left])) return error.InvalidBytecode;
                    if (!valueFits(program.graph, f.slots[x.dst], .{ .boolean = false }) or !types.equal(program.graph, f.slots[x.left], f.slots[x.right])) return error.InvalidBytecode;
                    const numeric = integerBounds(program.graph, f.slots[x.left]) != null or b.floatType(program.graph, f.slots[x.left]);
                    const equality_only = valueFits(program.graph, f.slots[x.left], .{ .boolean = false }) or types.variants(program.graph, f.slots[x.left]) != null;
                    const equality = x.operator == .equal or x.operator == .not_equal;
                    if (!numeric and !(equality_only and equality)) return error.InvalidBytecode;
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
                    if (!types.equal(program.graph, f.slots[x.dst], element) or x.kind.bounds() == null or x.kind != b.scalarKind(program.graph, f.slots[x.index])) return error.InvalidBytecode;
                },
                .choice => |x| {
                    if (x.ordinal != try b.variantOrdinal(program.graph, f.slots[x.dst], x.variant)) return error.InvalidBytecode;
                    const variant = try choiceVariant(program.graph, f.slots[x.dst], x.variant);
                    if (variant.payload_type) |payload_type| {
                        const payload = x.payload orelse return error.InvalidBytecode;
                        if (!types.equal(program.graph, f.slots[payload], payload_type)) return error.InvalidBytecode;
                    } else if (x.payload != null) return error.InvalidBytecode;
                },
                .payload => |x| {
                    if (x.ordinal != try b.variantOrdinal(program.graph, f.slots[x.src], x.variant)) return error.InvalidBytecode;
                    const variant = try choiceVariant(program.graph, f.slots[x.src], x.variant);
                    if (!types.equal(program.graph, f.slots[x.dst], variant.payload_type orelse return error.InvalidBytecode)) return error.InvalidBytecode;
                },
                .is_variant => |x| {
                    if (x.ordinal != try b.variantOrdinal(program.graph, f.slots[x.src], x.variant)) return error.InvalidBytecode;
                    _ = try choiceVariant(program.graph, f.slots[x.src], x.variant);
                    if (!valueFits(program.graph, f.slots[x.dst], .{ .boolean = false })) return error.InvalidBytecode;
                },
                .branch_storage_variant => |x| {
                    const info = try placeInfo(program, f.slots, x.place);
                    if (x.ordinal != try b.variantOrdinal(program.graph, info.ty, x.variant) or x.yes >= f.code.len or x.no >= f.code.len) return error.InvalidBytecode;
                },
                .branch_variant => |x| {
                    if (x.ordinal != try b.variantOrdinal(program.graph, f.slots[x.src], x.variant)) return error.InvalidBytecode;
                    _ = try choiceVariant(program.graph, f.slots[x.src], x.variant);
                    if (x.yes >= f.code.len or x.no >= f.code.len) return error.InvalidBytecode;
                },
                inline .borrow, .borrow_storage => |x| {
                    const target = try placeInfo(program, f.slots, x.place);
                    const pointer = program.graph.semanticType(f.slots[x.dst]);
                    if (pointer != .pointer or pointer.pointer.mutability != x.permission or !types.equal(program.graph, pointer.pointer.child, target.ty) or (x.permission == .read_write and !target.writable)) return error.InvalidBytecode;
                },
                .load => |x| {
                    const target = try placeInfo(program, f.slots, x.place);
                    if (!types.equal(program.graph, f.slots[x.dst], target.ty) or x.interpretation != b.loadInterpretation(program.graph, target.ty)) return error.InvalidBytecode;
                },
                .check_place => |place| _ = try placeInfo(program, f.slots, place),
                .capture_write => |x| {
                    if (x.dst >= f.write_destinations.len) return error.InvalidBytecode;
                    const target = try placeInfo(program, f.slots, x.place);
                    if (!target.writable or !types.equal(program.graph, f.write_destinations[x.dst], target.ty)) return error.InvalidBytecode;
                    if (!x.require_cleanup and owning_types[@intFromEnum(target.ty)]) return error.InvalidBytecode;
                },
                .check_write_cleanup, .activate_write_cleanup => |destination| {
                    if (destination >= f.write_destinations.len) return error.InvalidBytecode;
                },
                .store => |x| {
                    if (x.destination >= f.write_destinations.len or !types.equal(program.graph, f.slots[x.value], f.write_destinations[x.destination])) return error.InvalidBytecode;
                },
                .branch_cleanup => |x| {
                    _ = try placeInfo(program, f.slots, x.place);
                    if (x.yes >= f.code.len or x.no >= f.code.len) return error.InvalidBytecode;
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
                .memory_call => |x| {
                    if (@intFromEnum(x.function) >= program.graph.functions.items.len) return error.InvalidBytecode;
                    const selected = @import("memory_boundary.zig").classify(program.graph, x.function) orelse return error.InvalidBytecode;
                    if (!std.meta.eql(selected, x.operation)) return error.InvalidBytecode;
                    const callee = program.graph.function(x.function);
                    if (x.args.len != callee.input.len or x.outputs.len != callee.output.len) return error.InvalidBytecode;
                    for (x.args, program.graph.fields.items[callee.input.start..][0..callee.input.len]) |slot, field| if (!types.equal(program.graph, f.slots[slot], field.ty)) return error.InvalidBytecode;
                    for (x.outputs, program.graph.fields.items[callee.output.start..][0..callee.output.len]) |slot, field| if (!types.equal(program.graph, f.slots[slot], field.ty)) return error.InvalidBytecode;
                },
                .host_call => |x| {
                    if (x.function >= program.host_functions.len) return error.InvalidBytecode;
                    const callee = program.graph.function(program.host_functions[x.function].function);
                    if (x.args.len != callee.input.len or x.outputs.len != callee.output.len) return error.InvalidBytecode;
                    for (x.args, program.graph.fields.items[callee.input.start..][0..callee.input.len]) |slot, field|
                        if (!types.equal(program.graph, f.slots[slot], field.ty)) return error.InvalidBytecode;
                    for (x.outputs, program.graph.fields.items[callee.output.start..][0..callee.output.len], 0..) |slot, field, index| {
                        if (!types.equal(program.graph, f.slots[slot], field.ty)) return error.InvalidBytecode;
                        for (x.outputs[0..index]) |previous| if (previous == slot) return error.InvalidBytecode;
                    }
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
                .abort_, .trap => {},
            }
        }
        // A linear instruction does not need a retained input snapshot. Only
        // joins (including the implicit function-entry edge) can be revisited
        // with a stricter incoming state.
        const predecessors = try allocator.alloc(usize, f.code.len);
        defer allocator.free(predecessors);
        @memset(predecessors, 0);
        predecessors[0] = 1;
        for (f.code, 0..) |instruction, pc| {
            var edges: [2]u32 = undefined;
            const edge_count = successors(instruction, pc, f.code.len, &edges);
            for (edges[0..edge_count]) |next| predecessors[next] += 1;
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
        for (f.cleanup) |entry| {
            states[0].?[entry.flag] = 1;
            if (entry.presence) |flag| states[0].?[flag] = 1;
        }
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(allocator);
        try pending.append(allocator, 0);
        while (pending.pop()) |pc| {
            const initialized = if (predecessors[pc] == 1) owned: {
                const state = states[pc].?;
                states[pc] = null;
                break :owned state;
            } else try allocator.dupe(u8, states[pc].?);
            var transferred = false;
            defer if (!transferred) allocator.free(initialized);
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
            var edges: [2]u32 = undefined;
            const count = successors(inst, pc, f.code.len, &edges);
            if (count == 0 and inst.op != .ret and inst.op != .abort_ and inst.op != .trap) return error.InvalidBytecode;
            for (edges[0..count], 0..) |next, edge| {
                // An active cleanup branch proves that its concrete owner has
                // storage. Keep this fact on the active edge only; the vacant
                // path must still initialize the value before ordinary reads.
                var refined_root: ?Slot = null;
                if (inst.op == .branch_cleanup and edge == 0) {
                    const place = inst.op.branch_cleanup.place;
                    if (place.region == .local) {
                        var static_path = true;
                        for (place.path) |projection| if (projection == .dereference or projection == .element) {
                            static_path = false;
                        };
                        if (static_path and initialized[place.root] == 0) {
                            initialized[place.root] = 1;
                            refined_root = place.root;
                        }
                    }
                }
                defer if (refined_root) |root| {
                    initialized[root] = 0;
                };
                var changed = false;
                if (states[next]) |old| {
                    for (old, initialized) |*was, now| if (was.* != (was.* & now)) {
                        was.* &= now;
                        changed = true;
                    };
                } else {
                    if (count == 1) {
                        states[next] = initialized;
                        transferred = true;
                    } else states[next] = try allocator.dupe(u8, initialized);
                    changed = true;
                }
                if (changed) try pending.append(allocator, next);
            }
        }
    }
}

// Structural validation has already checked explicit branch targets.
fn successors(instruction: Instruction, pc: usize, length: usize, edges: *[2]u32) usize {
    return switch (instruction.op) {
        .ret, .abort_, .trap => 0,
        .jump => |target| result: {
            edges[0] = target;
            break :result 1;
        },
        inline .branch, .branch_cleanup, .branch_variant, .branch_storage_variant => |branch| result: {
            edges.* = .{ branch.yes, branch.no };
            break :result 2;
        },
        else => result: {
            if (pc + 1 >= length) return 0;
            edges[0] = @intCast(pc + 1);
            break :result 1;
        },
    };
}

fn destinations(i: Instruction, single: *[1]Slot) []const Slot {
    if (i.op == .call) return i.op.call.outputs;
    if (i.op == .host_call) return i.op.host_call.outputs;
    if (i.op == .memory_call) return i.op.memory_call.outputs;
    if (i.op == .virtual_call) return i.op.virtual_call.outputs;
    const slot: ?Slot = switch (i.op) {
        .constant => |x| x.dst,
        .reserve_storage => |x| x.dst,
        .borrow_storage => |x| x.dst,
        .static_bytes => |x| x.dst,
        .trace_location => |x| x.dst,
        .resolve_location => |x| x.dst,
        .virtualize => |x| x.dst,
        .numeric_bytes => |x| x.dst,
        .acquired_reference => |x| x.dst,
        .erase_reference => |x| x.dst,
        .offset_reference => |x| x.dst,
        .copy => |x| x.dst,
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
        .resolve_location => |x| try out.append(a, x.id),
        .virtualize => |x| try out.append(a, x.receiver),
        .virtual_call => |x| {
            try out.append(a, x.handle);
            try out.appendSlice(a, x.args);
        },
        .numeric_bytes => |x| try out.append(a, x.src),
        .acquired_reference => |x| try out.append(a, x.address),
        .erase_reference => |x| try out.append(a, x.src),
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
        .borrow_storage => |x| try readCleanupPlace(a, x.place, out),
        .load => |x| try readPlace(a, x.place, out),
        .check_place => |place| try readPlace(a, place, out),
        .capture_write => |x| try readPlace(a, x.place, out),
        .store => |x| try out.append(a, x.value),
        inline .cleanup_test, .branch_cleanup, .branch_storage_variant => |x| try readCleanupPlace(a, x.place, out),
        .cleanup_set => |x| try readCleanupPlace(a, x.place, out),
        .call => |x| try out.appendSlice(a, x.args),
        .host_call => |x| try out.appendSlice(a, x.args),
        .memory_call => |x| try out.appendSlice(a, x.args),
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
        if (entry.presence) |flag| {
            if (flag >= f.slots.len or flags[flag] or !valueFits(graph, f.slots[flag], .{ .boolean = false })) return error.InvalidBytecode;
            flags[flag] = true;
        }
        var ty = f.slots[entry.root];
        for (entry.path) |projection| switch (projection) {
            .field => |field| {
                const fields = types.fields(graph, ty) orelse return error.InvalidBytecode;
                if (field >= fields.len) return error.InvalidBytecode;
                ty = graph.fields.items[fields.start + field].ty;
            },
            .variant => |ordinal| ty = (try choiceVariant(graph, ty, try b.variantIdentity(graph, ty, ordinal))).payload_type orelse return error.InvalidBytecode,
            .element => |element| {
                if (element >= (types.arrayLength(graph, ty) orelse return error.InvalidBytecode)) return error.InvalidBytecode;
                ty = types.arrayElement(graph, ty) orelse return error.InvalidBytecode;
            },
        };
        if ((entry.presence != null) != (types.variants(graph, ty) != null)) return error.InvalidBytecode;
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
    else if (place.region == .global) blk: {
        for (program.globals) |global| if (@intFromEnum(global.binding) == place.root) break :blk global.ty;
        return error.InvalidBytecode;
    } else if (place.root < slots.len)
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
            if (index.slot >= slots.len or integerBounds(graph, slots[index.slot]) == null or !std.meta.eql(index.kind, b.scalarKind(graph, slots[index.slot]))) return error.InvalidBytecode;
            ty = types.arrayElement(graph, ty) orelse return error.InvalidBytecode;
        },
        .variant => |id| {
            if (id.ordinal != try b.variantOrdinal(graph, ty, id.identity)) return error.InvalidBytecode;
            const variant = try choiceVariant(graph, ty, id.identity);
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
        .element => |index| try out.append(a, index.slot),
        .field, .variant, .dereference => {},
    };
}

fn sessionBinding(program: Program, index: u32) !b.SessionBinding {
    const session = program.session orelse return error.InvalidBytecode;
    if (index >= session.bindings.len) return error.InvalidBytecode;
    return session.bindings[index];
}

test "bytecode load descriptors preserve erased anchors and target byte interpretation" {
    const a = std.testing.allocator;
    const p = @import("../../4_semantics/primitives/schema.zig");
    for ([_]p.BuiltinType{ .Int8, .UInt8, .Int32, .Any }) |builtin| {
        var graph: g.GlobalSemanticGraph = .{};
        defer graph.deinit(a);
        try graph.types.appendSlice(a, &.{
            .{ .builtin = builtin },
            .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } },
        });
        const selected = b.loadInterpretation(&graph, @enumFromInt(0));
        const source = p.SourceRef{ .file_index = 0, .offset = 0 };
        var code = [_]Instruction{
            .{ .source = source, .op = .{ .load = .{ .dst = 1, .place = .{ .root = 0, .path = &.{.dereference} }, .interpretation = selected } } },
            .{ .source = source, .op = .{ .ret = &.{1} } },
        };
        const function = b.Function{ .slots = &.{ @enumFromInt(1), @enumFromInt(0) }, .inputs = &.{0}, .outputs = &.{1}, .code = &code };
        const program = Program{ .graph = &graph, .functions = &.{}, .expression = &function };
        try verify(a, program);
        for (std.enums.values(b.LoadInterpretation)) |interpretation| {
            if (interpretation == selected) continue;
            code[0].op.load.interpretation = interpretation;
            try std.testing.expectError(error.InvalidBytecode, verify(a, program));
        }
    }
}

test "bytecode scalar descriptors preserve integer width sign and floating precision" {
    const a = std.testing.allocator;
    const p = @import("../../4_semantics/primitives/schema.zig");
    for ([_]p.BuiltinType{ .Int8, .UInt8, .Int16, .UInt16, .Int32, .UInt32, .Int64, .UInt64, .Float16, .Float32, .Float64 }) |builtin| {
        var graph: g.GlobalSemanticGraph = .{};
        defer graph.deinit(a);
        try graph.types.appendSlice(a, &.{ .{ .builtin = builtin }, .{ .builtin = .Bool } });
        const kind = b.scalarKind(&graph, @enumFromInt(0));
        try std.testing.expect(kind != .unresolved);
        const source = p.SourceRef{ .file_index = 0, .offset = 0 };
        var slots = [_]Type{ @enumFromInt(0), @enumFromInt(0), @enumFromInt(0) };
        var code = [_]Instruction{
            .{ .source = source, .op = .{ .binary = .{ .dst = 2, .left = 0, .right = 1, .operator = .addition, .kind = kind } } },
            .{ .source = source, .op = .{ .ret = &.{2} } },
        };
        const function = b.Function{ .slots = &slots, .inputs = &.{ 0, 1 }, .outputs = &.{2}, .code = &code };
        const program = Program{ .graph = &graph, .functions = &.{}, .expression = &function };
        try verify(a, program);
        code[0].op.binary.kind = .unresolved;
        try std.testing.expectError(error.InvalidBytecode, verify(a, program));
        code[0].op.binary.kind = if (kind == .u8) .i8 else .u8;
        try std.testing.expectError(error.InvalidBytecode, verify(a, program));
        slots[2] = @enumFromInt(1);
        code[0].op = .{ .compare = .{ .dst = 2, .left = 0, .right = 1, .operator = .less_than, .kind = kind } };
        try verify(a, program);
        code[0].op.compare.kind = if (kind == .f32) .f64 else .f32;
        try std.testing.expectError(error.InvalidBytecode, verify(a, program));
    }
}

test "bytecode borrow descriptors cannot change the selected access permission" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
    });
    const source = @import("../../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    for ([_]bool{ false, true }) |storage| {
        var code = [_]Instruction{
            .{ .source = source, .op = .{ .constant = .{ .dst = 0, .value = .{ .integer = 42 } } } },
            .{ .source = source, .op = .abort_ },
            .{ .source = source, .op = .{ .ret = &.{1} } },
        };
        var slots = [_]Type{ @enumFromInt(0), @enumFromInt(1) };
        const function = b.Function{ .slots = &slots, .inputs = &.{}, .outputs = &.{1}, .code = &code };
        const program = Program{ .graph = &graph, .functions = &.{}, .expression = &function };
        for ([_]@import("../../4_semantics/primitives/schema.zig").PointerMutability{ .read_only, .read_write }) |permission| {
            code[1].op = if (storage)
                .{ .borrow_storage = .{ .dst = 1, .place = .{ .root = 0, .path = &.{} }, .permission = permission } }
            else
                .{ .borrow = .{ .dst = 1, .place = .{ .root = 0, .path = &.{} }, .permission = permission } };
            slots[1] = if (permission == .read_only) @enumFromInt(1) else @enumFromInt(2);
            try verify(a, program);
            slots[1] = if (permission == .read_only) @enumFromInt(2) else @enumFromInt(1);
            try std.testing.expectError(error.InvalidBytecode, verify(a, program));
        }
    }
}

test "bytecode numeric byte descriptors preserve selected permissions and endianness" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .UInt32 },
        .{ .builtin = .UInt8 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
        .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_write } },
        .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_only } },
    });
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const layout = try @import("numeric_layout.zig").compile(arena.allocator(), &graph, @enumFromInt(0));
    const endian = graph.target.arch.endian();
    const source = @import("../../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    var code = [_]Instruction{
        .{ .source = source, .op = .{ .numeric_bytes = .{ .dst = 1, .src = 0, .layout = layout, .permission = .read_write, .endian = endian } } },
        .{ .source = source, .op = .{ .ret = &.{1} } },
    };
    var slots = [_]Type{ @enumFromInt(2), @enumFromInt(3) };
    const function = b.Function{ .slots = &slots, .inputs = &.{0}, .outputs = &.{1}, .code = &code };
    const program = Program{ .graph = &graph, .functions = &.{}, .expression = &function };
    try verify(a, program);
    code[0].op.numeric_bytes.permission = .read_only;
    try std.testing.expectError(error.InvalidBytecode, verify(a, program));
    slots[1] = @enumFromInt(4);
    try verify(a, program);
    code[0].op.numeric_bytes.permission = .read_write;
    try std.testing.expectError(error.InvalidBytecode, verify(a, program));
    code[0].op.numeric_bytes.permission = .read_only;
    code[0].op.numeric_bytes.endian = if (endian == .little) .big else .little;
    try std.testing.expectError(error.InvalidBytecode, verify(a, program));
}

test "bytecode verifier allocation scaling for linear functions" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Bool });
    for ([_]usize{ 10, 100, 1000 }) |count| {
        const slots = try a.alloc(Type, count);
        defer a.free(slots);
        @memset(slots, @enumFromInt(0));
        const code = try a.alloc(Instruction, count + 1);
        defer a.free(code);
        for (code[0..count], 0..) |*instruction, slot| instruction.* = .{
            .source = .{ .file_index = 0, .offset = 0 },
            .op = .{ .constant = .{ .dst = @intCast(slot), .value = .{ .boolean = true } } },
        };
        const output = [_]Slot{@intCast(count - 1)};
        code[count] = .{ .source = .{ .file_index = 0, .offset = 0 }, .op = .{ .ret = &output } };
        const function = b.Function{ .slots = slots, .inputs = &.{}, .outputs = &output, .code = code };
        var bytes: u64 = 0;
        var allocations = @import("../../1_base/profile.zig").AllocationCounter{ .child = a, .requested_bytes = &bytes };
        try verify(allocations.allocator(), .{ .graph = &graph, .functions = &.{}, .expression = &function });
        // Requested allocation traffic remains linear in instructions plus
        // slots for straight-line code; timing is intentionally not asserted.
        try std.testing.expect(bytes <= count * 64 + 2048);
    }
}

fn verifyJoinAllocationFailures(a: std.mem.Allocator) !void {
    const owner = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(owner);
    try graph.types.append(owner, .{ .builtin = .Bool });
    const source = @import("../../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const slots = [_]Type{ @enumFromInt(0), @enumFromInt(0) };
    const code = [_]Instruction{
        .{ .source = source, .op = .{ .branch = .{ .condition = 0, .yes = 1, .no = 3 } } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 1, .value = .{ .boolean = true } } } },
        .{ .source = source, .op = .{ .jump = 5 } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 1, .value = .{ .boolean = false } } } },
        .{ .source = source, .op = .{ .jump = 5 } },
        .{ .source = source, .op = .{ .ret = &.{1} } },
    };
    const function = b.Function{ .slots = &slots, .inputs = &.{0}, .outputs = &.{1}, .code = &code };
    try verify(a, .{ .graph = &graph, .functions = &.{}, .expression = &function });
    var missing = code;
    missing[3] = .{ .source = source, .op = .{ .jump = 5 } };
    var incomplete = function;
    incomplete.code = &missing;
    verify(a, .{ .graph = &graph, .functions = &.{}, .expression = &incomplete }) catch |err| {
        if (err == error.OutOfMemory) return err;
        return std.testing.expectEqual(error.UninitializedBytecodeSlot, err);
    };
    return error.ExpectedInitializationRejection;
}

test "bytecode verifier retains join intersections and releases transferred states on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, verifyJoinAllocationFailures, .{});
}

test "bytecode verifier loop backedges cannot initialize the function entry" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Bool });
    const source = @import("../../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const code = [_]Instruction{
        .{ .source = source, .op = .{ .branch = .{ .condition = 0, .yes = 1, .no = 3 } } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 1, .value = .{ .boolean = true } } } },
        .{ .source = source, .op = .{ .jump = 0 } },
        .{ .source = source, .op = .{ .ret = &.{1} } },
    };
    var function = b.Function{ .slots = &.{ @enumFromInt(0), @enumFromInt(0) }, .inputs = &.{0}, .outputs = &.{1}, .code = &code };
    const program = Program{ .graph = &graph, .functions = &.{}, .expression = &function };
    try std.testing.expectError(error.UninitializedBytecodeSlot, verify(a, program));
    function.inputs = &.{ 0, 1 };
    try verify(a, program);
}
