//! Associated projections use selected evidence without return-based inference.
const std = @import("std");
const module_views = @import("../module/views.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const generic_mod = @import("generics.zig");
const primitives = @import("../primitives/schema.zig");

const Resolver = @import("contracts.zig").Resolver;
pub fn resolveAssociatedType(context: *anyopaque, base: global_sg.GlobalTypeId, member: []const u8, source: primitives.SourceRef) anyerror!global_sg.GlobalTypeId {
    const self: *Resolver = @ptrCast(@alignCast(context));
    return (try resolveAssociatedElement(self, base, member, source, true)).type;
}

pub fn resolveAssociatedInt(context: *anyopaque, base: global_sg.GlobalTypeId, member: []const u8, source: primitives.SourceRef) anyerror!i64 {
    const self: *Resolver = @ptrCast(@alignCast(context));
    return (try resolveAssociatedElement(self, base, member, source, false)).comptime_int;
}

fn resolveAssociatedElement(self: *Resolver, base: global_sg.GlobalTypeId, member: []const u8, source: primitives.SourceRef, want_type: bool) anyerror!global_sg.GenericArgument.Value {
    if (self.graph.isTypeUnresolved(base)) return error.UnresolvedAssociatedType;
    const generic = switch (self.graph.types.items[@intFromEnum(base)]) {
        .generic => |value| value,
        else => return associatedProjectionError(self, want_type, source, "associated projection requires a participant contract", member),
    };
    const located = self.findContractDefinition(generic.base) orelse
        return associatedProjectionError(self, want_type, source, "associated projection requires a participant contract", member);
    if (!located.definition.hasExplicitParticipants())
        return associatedProjectionError(self, want_type, source, "associated projection requires explicit contract participants", member);
    const storage = &self.modules[located.module_index].semantic.parameterized_storage;
    var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
    defer bindings.deinit(self.allocator);
    self.generics.bindGlobalArguments(located.module_index, located.definition.participants, generic.arguments, &bindings) catch |err| {
        return associatedProjectionError(self, want_type, source, Resolver.conformanceArgumentFailure(err) orelse return err, member);
    };
    for (located.definition.participants.start..located.definition.participants.start + located.definition.participants.len) |raw| {
        if (!typeSelectionReady(self, bindings.types[raw].?, 0)) return error.UnresolvedAssociatedType;
    }
    var position: ?usize = null;
    for (0..located.definition.parameters.len) |i| {
        const parameter = storage.comptime_parameters.items[located.definition.parameters.start + i];
        if (std.mem.eql(u8, self.modules[located.module_index].text(parameter.name), member)) {
            if ((parameter.kind == .type) != want_type) return associatedProjectionError(self, want_type, source, if (want_type) "associated element is not a type" else "associated element is not an integer constant", member);
            position = i;
            break;
        }
    }
    const associated_index = position orelse return associatedProjectionError(self, want_type, source, if (want_type) "unknown associated type" else "unknown associated constant", member);
    var participants: std.ArrayList(global_sg.GlobalTypeId) = .empty;
    defer participants.deinit(self.allocator);
    for (located.definition.participants.start..located.definition.participants.start + located.definition.participants.len) |raw|
        try participants.append(self.allocator, bindings.types[raw].?);
    var deferred = false;
    if (try self.selectConformance(generic.base, participants.items, &bindings, 0, &deferred)) |selection| {
        const conformance = self.graph.contract_conformances.items[selection.tuple];
        const result = @import("contract_evidence.zig").associatedElement(self.graph, conformance, associated_index) orelse return error.InvalidContractAssociatedElement;
        if (result == .type and !typeSelectionReady(self, result.type, 0)) return error.UnresolvedAssociatedType;
        return result;
    }
    if (deferred) return error.UnresolvedAssociatedType;
    return associatedProjectionError(self, want_type, source, "no conformance for the projected participant tuple", member);
}

pub fn typeSelectionReady(self: *const Resolver, ty: global_sg.GlobalTypeId, depth: usize) bool {
    if (depth > 128 or self.graph.isTypeUnresolved(ty)) return false;
    return switch (self.graph.types.items[@intFromEnum(ty)]) {
        .pointer => |value| typeSelectionReady(self, value.child, depth + 1),
        .array => |value| typeSelectionReady(self, value.element, depth + 1),
        .nullable, .inferred_errable, .virtual => |child| typeSelectionReady(self, child, depth + 1),
        .generic => |value| blk: {
            for (self.graph.generic_arguments.items[value.arguments.start..][0..value.arguments.len]) |argument| {
                if (argument.value == .type and !typeSelectionReady(self, argument.value.type, depth + 1)) break :blk false;
            }
            break :blk true;
        },
        .structural => |value| blk: {
            for (self.graph.fields.items[value.fields.start..][0..value.fields.len]) |field|
                if (!typeSelectionReady(self, field.ty, depth + 1)) break :blk false;
            break :blk true;
        },
        .structural_choice => |value| blk: {
            for (self.graph.variants.items[value.variants.start..][0..value.variants.len]) |variant|
                if (variant.payload_type) |child| if (!typeSelectionReady(self, child, depth + 1)) break :blk false;
            break :blk true;
        },
        else => true,
    };
}

fn associatedProjectionError(self: *Resolver, want_type: bool, source: primitives.SourceRef, reason: []const u8, member: []const u8) error{InvalidAssociatedTypeProjection} {
    self.participant_conformance_failure = .{ .is_projection = true, .is_value_projection = !want_type, .source = source, .contract_name = member, .reason = reason };
    return error.InvalidAssociatedTypeProjection;
}

fn projectionError(self: *Resolver, source: primitives.SourceRef, reason: []const u8, member: []const u8) error{InvalidAssociatedTypeProjection} {
    self.participant_conformance_failure = .{ .is_projection = true, .source = source, .contract_name = member, .reason = reason };
    return error.InvalidAssociatedTypeProjection;
}

pub fn resolveAssociatedTypes(self: *Resolver) !void {
    var remaining: usize = 0;
    while (true) {
        var changed = false;
        remaining = 0;
        for (self.modules, 0..) |*module, module_index| {
            const o = self.offsets[module_index];
            for (0..module_views.typeCount(module)) |raw| {
                const local: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw)));
                const value = try module_views.typeView(module, local);
                const external = switch (value) {
                    .external => |id| id,
                    else => continue,
                };
                const reference = module.semantic.external_refs.items[@intFromEnum(external)];
                if (reference.projection_base == null and reference.computed_type == null) continue;
                const destination = globalizer.globalType(o, local);
                if (!self.graph.isTypeUnresolved(destination)) continue;
                const result = (if (reference.computed_type) |computed| blk: {
                    var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
                    defer bindings.deinit(self.allocator);
                    break :blk self.generics.instantiateParameterizedType(module_index, computed, &bindings);
                } else resolveAssociatedType(self, globalizer.globalType(o, reference.projection_base.?), module.text(reference.name), self.sourceFor(module_index, reference.source))) catch |err| switch (err) {
                    error.ComptimeExecutionPending => continue,
                    error.UnresolvedAssociatedType => {
                        remaining += 1;
                        continue;
                    },
                    else => return err,
                };
                try self.graph.resolveType(self.allocator, destination, self.graph.types.items[@intFromEnum(result)]);
                changed = true;
            }
        }
        if (remaining == 0) return;
        if (!changed) {
            for (self.modules, 0..) |*module, module_index| {
                for (0..module_views.typeCount(module)) |raw| {
                    const local: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw)));
                    const value = try module_views.typeView(module, local);
                    const external = switch (value) {
                        .external => |id| id,
                        else => continue,
                    };
                    const reference = module.semantic.external_refs.items[@intFromEnum(external)];
                    if ((reference.projection_base == null and reference.computed_type == null) or !self.graph.isTypeUnresolved(globalizer.globalType(self.offsets[module_index], local))) continue;
                    return projectionError(self, self.sourceFor(module_index, reference.source), "cyclic or unresolved associated type projection", module.text(reference.name));
                }
            }
            unreachable;
        }
    }
}
