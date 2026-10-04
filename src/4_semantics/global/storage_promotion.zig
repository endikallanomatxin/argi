const std = @import("std");
const g = @import("graph.zig");
const types = @import("types.zig");
const p = @import("../primitives/schema.zig");
const diagnostic = @import("../../1_base/diagnostic.zig");
const summaries = @import("../safety/summaries.zig");
const facts = @import("../safety/facts.zig");
const inference_mod = @import("../safety/summary_infer.zig");

// Retention is a storage obligation, not an allocation receipt. The source
// signature remains unchanged; codegen supplies its hidden frame separately.
// Provisional safety summaries distinguish borrowing a value from borrowing
// its slot, so existing caller-backed views do not acquire spurious frames.
pub fn prepare(allocator: std.mem.Allocator, graph: *g.GlobalSemanticGraph, diagnostics: *diagnostic.Diagnostics, engine: *summaries.Engine, inference: *inference_mod.Infer) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp = arena.allocator();
    var pass = Pass{
        .allocator = temp,
        .graph = graph,
        .engine = engine,
        .inference = inference,
        .loop_bindings = std.AutoHashMap(g.GlobalBindingId, void).init(temp),
        .loop_calls = std.AutoHashMap(g.GlobalNodeId, void).init(temp),
    };
    pass.nodes = try temp.alloc([]const g.GlobalNodeId, graph.functions.items.len);
    pass.owners = try temp.alloc(?g.GlobalFunctionId, graph.bindings.items.len);
    @memset(pass.owners, null);
    try graph.retained_call_owners.resize(allocator, graph.nodes.items.len);
    @memset(graph.retained_call_owners.items, null);
    try graph.retained_storage.resize(allocator, graph.functions.items.len);
    @memset(graph.retained_storage.items, .{});
    for (graph.functions.items, 0..) |function, raw| {
        pass.function = @enumFromInt(@as(u32, @intCast(raw)));
        pass.seen = std.AutoHashMap(g.GlobalNodeId, void).init(temp);
        pass.list = .empty;
        for (graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]) |binding| pass.owners[@intFromEnum(binding)] = pass.function;
        for (graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |binding| {
            pass.owners[@intFromEnum(binding)] = pass.function;
            if (graph.binding(binding).initialization) |node| {
                pass.receiving_binding = binding;
                try pass.walk(node);
                pass.receiving_binding = null;
            }
        }
        if (function.body) |body| try pass.walkValue(body);
        pass.nodes[raw] = try pass.list.toOwnedSlice(temp);
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (graph.functions.items, 0..) |function, raw| {
            if (function.body == null or function.flags.is_c_abi) continue;
            pass.function = @enumFromInt(@as(u32, @intCast(raw)));
            pass.retained = .empty;
            pass.calls = .empty;
            pass.dependencies = std.AutoHashMap(g.GlobalNodeId, void).init(temp);
            const output_ids = graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len];
            for (output_ids) |binding| if (hasPointers(graph, graph.binding(binding).ty, 0)) {
                try pass.bindingValue(binding);
            };
            for (pass.nodes[raw]) |id| switch (graph.node(id).content) {
                .error_propagation => |v| try pass.depend(graph.error_propagations.items[@intFromEnum(v)].errable_value),
                .error_context => |v| try pass.depend(graph.error_contexts.items[@intFromEnum(v)].errable_value),
                else => {},
            };
            // A delayed destructor may itself borrow local capabilities. Keep
            // those dependencies in the frame, rather than dangling at return.
            var cursor: usize = 0;
            var cleanup: std.ArrayList(g.GlobalAutoDeinitId) = .empty;
            while (cursor < pass.retained.items.len) : (cursor += 1) {
                const binding = pass.retained.items[cursor];
                for (pass.nodes[raw]) |node| if (graph.node(node).content == .auto_deinit_binding) {
                    const id = graph.node(node).content.auto_deinit_binding;
                    const auto = graph.auto_deinits.items[@intFromEnum(id)];
                    if (auto.binding != binding) continue;
                    if (std.mem.indexOfScalar(g.GlobalAutoDeinitId, cleanup.items, id) == null) try cleanup.append(temp, id);
                    if (auto.input) |input| try pass.capture(input);
                    try pass.captureFields(auto.fields);
                };
            }
            std.mem.sort(g.GlobalAutoDeinitId, cleanup.items, {}, struct {
                fn less(_: void, left: g.GlobalAutoDeinitId, right: g.GlobalAutoDeinitId) bool {
                    return @intFromEnum(left) < @intFromEnum(right);
                }
            }.less);
            const old = graph.retained_storage.items[raw];
            if (old.bindings.len != pass.retained.items.len or old.calls.len != pass.calls.items.len) changed = true;
            allocator.free(old.bindings);
            allocator.free(old.calls);
            allocator.free(old.cleanup);
            graph.retained_storage.items[raw] = .{
                .bindings = try allocator.dupe(g.GlobalBindingId, pass.retained.items),
                .calls = try allocator.dupe(g.GlobalNodeId, pass.calls.items),
                .cleanup = try allocator.dupe(g.GlobalAutoDeinitId, cleanup.items),
            };
        }
    }
    var loop_bindings = pass.loop_bindings.keyIterator();
    while (loop_bindings.next()) |binding| if (graph.retainedBinding(binding.*)) {
        const source = graph.binding(binding.*).source;
        try diagnostics.add(.{ .file = @enumFromInt(source.file_index), .offset = source.offset }, .semantic, "returned references retain repeatedly created local storage; use an explicit allocator for the referenced values", .{});
        return error.Reported;
    };
    var loop_calls = pass.loop_calls.keyIterator();
    while (loop_calls.next()) |node| if (graph.retained_storage.items[@intFromEnum(graph.node(node.*).content.function_call.callee)].present()) {
        const source = graph.node(node.*).source;
        try diagnostics.add(.{ .file = @enumFromInt(source.file_index), .offset = source.offset }, .semantic, "repeated calls retain local storage with no bounded caller frame; use an explicit allocator for the referenced values", .{});
        return error.Reported;
    };
    for (graph.virtualizes.items) |virtualize| for (graph.function_refs.items[virtualize.methods.start..][0..virtualize.methods.len]) |method| if (graph.retained_storage.items[@intFromEnum(method)].present()) {
        const source = virtualize.source;
        try diagnostics.add(.{ .file = @enumFromInt(source.file_index), .offset = source.offset }, .semantic, "virtual methods cannot return local storage requiring a caller frame; use an explicit allocator for the referenced values", .{});
        return error.Reported;
    };
    // Finite frames can be forwarded through a DAG. Recursive retention needs
    // a separately bounded representation and cannot silently use the heap.
    const visiting = try temp.alloc(u8, graph.functions.items.len);
    @memset(visiting, 0);
    for (graph.retained_storage.items, 0..) |frame, raw| if (frame.present()) {
        if (try cyclic(graph, @enumFromInt(@as(u32, @intCast(raw))), visiting)) {
            const source = graph.declarations.items[@intFromEnum(graph.functions.items[raw].declaration)].source;
            try diagnostics.add(.{ .file = @enumFromInt(source.file_index), .offset = source.offset }, .semantic, "returned local storage requires a bounded caller frame; recursive retention is not supported", .{});
            return error.Reported;
        }
    };
}

fn cyclic(graph: *const g.GlobalSemanticGraph, function: g.GlobalFunctionId, visiting: []u8) !bool {
    const raw = @intFromEnum(function);
    if (visiting[raw] == 1) return true;
    if (visiting[raw] == 2) return false;
    visiting[raw] = 1;
    for (graph.retained_storage.items[raw].calls) |node| {
        if (try cyclic(graph, graph.node(node).content.function_call.callee, visiting)) return true;
    }
    visiting[raw] = 2;
    return false;
}

pub fn hasPointers(graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, depth: usize) bool {
    if (depth > 32) return true;
    const semantic = graph.semanticType(ty);
    if (semantic == .pointer or semantic == .virtual) return true;
    if (semantic == .nullable) return hasPointers(graph, semantic.nullable, depth + 1);
    if (types.fields(graph, ty)) |fields| for (graph.fields.items[fields.start..][0..fields.len]) |field| {
        if (hasPointers(graph, field.ty, depth + 1)) return true;
    };
    if (types.variants(graph, ty)) |variants| for (graph.variants.items[variants.start..][0..variants.len]) |variant| {
        if (variant.payload_type) |child| if (hasPointers(graph, child, depth + 1)) return true;
    };
    if (types.arrayElement(graph, ty)) |element| return hasPointers(graph, element, depth + 1);
    return false;
}

const Pass = struct {
    allocator: std.mem.Allocator,
    graph: *g.GlobalSemanticGraph,
    engine: *summaries.Engine,
    inference: *inference_mod.Infer,
    function: g.GlobalFunctionId = @enumFromInt(0),
    receiving_binding: ?g.GlobalBindingId = null,
    inside_loop: bool = false,
    loop_bindings: std.AutoHashMap(g.GlobalBindingId, void),
    loop_calls: std.AutoHashMap(g.GlobalNodeId, void),
    owners: []?g.GlobalFunctionId = &.{},
    nodes: [][]const g.GlobalNodeId = &.{},
    list: std.ArrayList(g.GlobalNodeId) = .empty,
    seen: std.AutoHashMap(g.GlobalNodeId, void) = undefined,
    dependencies: std.AutoHashMap(g.GlobalNodeId, void) = undefined,
    retained: std.ArrayList(g.GlobalBindingId) = .empty,
    calls: std.ArrayList(g.GlobalNodeId) = .empty,

    fn walk(self: *Pass, node: g.GlobalNodeId) anyerror!void {
        if ((try self.seen.getOrPut(node)).found_existing) return;
        try self.list.append(self.allocator, node);
        const content = self.graph.node(node).content;
        const previous_loop = self.inside_loop;
        if (content == .while_statement or content == .for_statement) self.inside_loop = true;
        defer self.inside_loop = previous_loop;
        if (self.inside_loop and content == .function_call) try self.loop_calls.put(node, {});
        const previous_receiver = self.receiving_binding;
        defer self.receiving_binding = previous_receiver;
        if (content == .assignment) self.receiving_binding = content.assignment.binding;
        if (content == .struct_field_store) self.receiving_binding = self.root(content.struct_field_store.struct_ptr);
        if (content == .array_store) self.receiving_binding = self.root(content.array_store.array_ptr);
        if (content == .pointer_assignment) self.receiving_binding = self.root(content.pointer_assignment.pointer);
        if (content == .function_call) self.graph.retained_call_owners.items[@intFromEnum(node)] = self.receiving_binding;
        if (content == .binding_declaration) {
            self.receiving_binding = content.binding_declaration;
            if (self.inside_loop) try self.loop_bindings.put(content.binding_declaration, {});
            self.owners[@intFromEnum(content.binding_declaration)] = self.function;
            if (self.graph.binding(content.binding_declaration).initialization) |value| try self.walk(value);
        }
        try self.walkValue(content);
    }

    fn walkValue(self: *Pass, value: anytype) anyerror!void {
        const T = @TypeOf(value);
        if (T == g.GlobalNodeId) return self.walk(value);
        if (T == g.GlobalBlockId) return self.walkValue(self.graph.blocks.items[@intFromEnum(value)]);
        if (T == g.GlobalErrorPropagationId) return self.walkValue(self.graph.error_propagations.items[@intFromEnum(value)]);
        if (T == g.GlobalErrorContextId) return self.walkValue(self.graph.error_contexts.items[@intFromEnum(value)]);
        if (T == g.GlobalVirtualizeId) return self.walkValue(self.graph.virtualizes.items[@intFromEnum(value)]);
        if (T == g.GlobalVirtualCallId) return self.walkValue(self.graph.virtual_calls.items[@intFromEnum(value)]);
        if (T == g.GlobalSwitchId) return self.walkValue(self.graph.switches.items[@intFromEnum(value)]);
        if (T == g.GlobalNullableUnwrapId) return self.walkValue(self.graph.nullable_unwraps.items[@intFromEnum(value)]);
        switch (@typeInfo(T)) {
            .@"struct" => inline for (std.meta.fields(T)) |field| {
                const child = @field(value, field.name);
                // Range(T) intentionally erases T. Select the backing table
                // from the field's role, never from its Zig type identity.
                if (@TypeOf(child) == p.Range(g.GlobalNodeId)) {
                    if (comptime std.mem.eql(u8, field.name, "nodes") or std.mem.eql(u8, field.name, "elements") or std.mem.eql(u8, field.name, "cleanup") or std.mem.eql(u8, field.name, "cleanup_nodes")) {
                        for (self.graph.node_refs.items[child.start..][0..child.len]) |node| try self.walk(node);
                    } else if (comptime std.mem.eql(u8, field.name, "fields") or std.mem.eql(u8, field.name, "assumed_fields")) {
                        for (self.graph.value_fields.items[child.start..][0..child.len]) |entry| try self.walk(entry.value);
                    } else if (comptime std.mem.eql(u8, field.name, "cases")) {
                        for (self.graph.switch_cases.items[child.start..][0..child.len]) |case| {
                            if (case.payload_binding) |binding| self.owners[@intFromEnum(binding)] = self.function;
                            try self.walkValue(case);
                        }
                    }
                } else try self.walkValue(child);
            },
            .@"union" => if (@typeInfo(T).@"union".tag_type != null) {
                inline for (std.meta.fields(T)) |field| if (std.mem.eql(u8, @tagName(value), field.name)) try self.walkValue(@field(value, field.name));
            },
            .optional => if (value) |child| try self.walkValue(child),
            else => {},
        }
    }

    fn retain(self: *Pass, binding: g.GlobalBindingId) !void {
        if (self.owners[@intFromEnum(binding)] != self.function) return;
        if (std.mem.indexOfScalar(g.GlobalBindingId, self.retained.items, binding) == null) try self.retained.append(self.allocator, binding);
    }

    fn bindingValue(self: *Pass, binding: g.GlobalBindingId) anyerror!void {
        if (self.graph.binding(binding).initialization) |node| try self.depend(node);
        for (self.nodes[@intFromEnum(self.function)]) |node| switch (self.graph.node(node).content) {
            .assignment => |assignment| if (assignment.binding == binding) {
                try self.depend(assignment.value);
            },
            .struct_field_store => |store| if (self.root(store.struct_ptr) == binding) {
                try self.depend(store.value);
            },
            .array_store => |store| if (self.root(store.array_ptr) == binding) {
                try self.depend(store.value);
            },
            .pointer_assignment => |store| if (self.root(store.pointer) == binding) {
                try self.depend(store.value);
            },
            else => {},
        };
    }

    fn root(self: *Pass, node: g.GlobalNodeId) ?g.GlobalBindingId {
        return switch (self.graph.node(node).content) {
            .binding_use => |binding| binding,
            .address_of => |value| self.root(value),
            .struct_field_access => |field| self.root(field.value),
            .array_index => |index| self.root(index.array_ptr),
            else => null,
        };
    }

    fn depend(self: *Pass, node: g.GlobalNodeId) anyerror!void {
        if ((try self.dependencies.getOrPut(node)).found_existing) return;
        const value = self.graph.node(node);
        switch (value.content) {
            .binding_use => |binding| try self.bindingValue(binding),
            .address_of => |child| {
                if (self.root(child)) |binding| try self.retain(binding);
                try self.depend(child);
            },
            .function_call => |call| {
                if (self.graph.retained_storage.items[@intFromEnum(call.callee)].present()) {
                    if (std.mem.indexOfScalar(g.GlobalNodeId, self.calls.items, node) == null) try self.calls.append(self.allocator, node);
                    if (self.graph.retained_call_owners.items[@intFromEnum(node)]) |receiver| {
                        const function = self.graph.function(self.function);
                        const outputs = self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len];
                        if (std.mem.indexOfScalar(g.GlobalBindingId, outputs, receiver) == null)
                            try self.retain(receiver);
                    }
                }
                if (value.ty) |ty| if (hasPointers(self.graph, ty, 0)) {
                    if (self.graph.retained_storage.items[@intFromEnum(call.callee)].present()) {
                        try self.depend(call.input);
                    } else if (self.graph.function(call.callee).safety_primitive != .none) {
                        if (self.graph.node(call.input).content == .struct_value_literal) {
                            const effect = try self.inference.primitiveValueEffect(self.graph.function(call.callee).safety_primitive, @intFromEnum(node));
                            try self.dependEffect(effect, self.graph.node(call.input).content.struct_value_literal.fields);
                        }
                    } else if (self.engine.summaryFor(call.callee)) |summary| {
                        if (self.graph.node(call.input).content == .struct_value_literal) {
                            const fields = self.graph.node(call.input).content.struct_value_literal.fields;
                            for (summary.outputs) |effect| try self.dependEffect(effect, fields);
                        }
                    }
                };
            },
            .struct_value_literal => |literal| for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
                try self.depend(field.value);
            },
            .array_literal => |literal| for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |child| {
                try self.depend(child);
            },
            .struct_field_access => |field| try self.depend(field.value),
            .choice_payload_access => |payload| try self.depend(payload.value),
            .choice_literal => |literal| if (literal.payload) |payload| {
                try self.depend(payload);
            },
            .dereference => |read| try self.depend(read.pointer),
            .virtualize => |id| try self.depend(self.graph.virtualizes.items[@intFromEnum(id)].value),
            .move_value, .denied_implicit_copy => |child| try self.depend(child),
            .value_sequence => |id| if (self.graph.blocks.items[@intFromEnum(id)].ret_val) |child| {
                try self.depend(child);
            },
            .error_propagation => |id| try self.depend(self.graph.error_propagations.items[@intFromEnum(id)].errable_value),
            .error_context => |id| try self.depend(self.graph.error_contexts.items[@intFromEnum(id)].errable_value),
            .explicit_cast => |cast| try self.depend(cast.value),
            else => {},
        }
    }

    fn dependArgument(self: *Pass, path: facts.InputPath, fields: p.Range(g.GlobalValueFieldId), value_only: bool) anyerror!void {
        if (path.input_index >= fields.len) return;
        const argument = self.graph.value_fields.items[fields.start + path.input_index].value;
        if (value_only and self.graph.node(argument).content == .address_of) {
            const child = self.graph.node(argument).content.address_of;
            if (self.root(child)) |binding| {
                // Owned contents need their destructor delayed. Plain borrowed
                // wrappers need only the dependencies of the value they carry.
                for (self.graph.auto_deinits.items) |auto| if (auto.binding == binding and (auto.deinit_fn != null or auto.fields.len != 0)) {
                    try self.retain(binding);
                    break;
                };
            }
            try self.depend(child);
        } else try self.depend(argument);
    }

    fn dependEffect(self: *Pass, effect: facts.ValueEffect, fields: p.Range(g.GlobalValueFieldId)) anyerror!void {
        for (effect.input_dependencies) |dependency| try self.dependArgument(dependency.path, fields, dependency.path.projections.len != 0);
        for (effect.input_places) |path| try self.dependArgument(path, fields, false);
        for (effect.input_generation_dependencies) |path| try self.dependArgument(path, fields, false);
        for (effect.input_place_values) |path| try self.dependArgument(path, fields, true);
        for (effect.opaque_generation_dependencies) |path| try self.dependArgument(path, fields, true);
        for (effect.opaque_storage_dependencies) |path| try self.dependArgument(path, fields, true);
        for (effect.fields) |field| try self.dependEffect(field.value.*, fields);
        for (effect.variants) |variant| try self.dependEffect(variant.value.*, fields);
    }

    fn capture(self: *Pass, node: g.GlobalNodeId) anyerror!void {
        switch (self.graph.node(node).content) {
            .binding_use => |binding| {
                try self.retain(binding);
                try self.bindingValue(binding);
            },
            .address_of => |child| try self.capture(child),
            .struct_field_access => |field| try self.capture(field.value),
            .struct_value_literal => |literal| for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
                try self.capture(field.value);
            },
            else => try self.depend(node),
        }
    }

    fn captureFields(self: *Pass, fields: p.Range(g.GlobalAutoDeinitFieldId)) anyerror!void {
        for (self.graph.auto_deinit_fields.items[fields.start..][0..fields.len]) |field| {
            if (field.input) |input| try self.capture(input);
            try self.captureFields(field.fields);
        }
    }
};
