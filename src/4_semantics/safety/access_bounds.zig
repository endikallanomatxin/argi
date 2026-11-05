//! Mapped access regions share storage-domain and caller-relative coordinates.
const std = @import("std");
const g = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const schema = @import("../primitives/schema.zig");
const facts = @import("safety_facts.zig");
const contracts = @import("contracts.zig");
const Projection = @import("place.zig").Projection;

/// Internal domain for the erased receiver itself, distinct from its handle.
pub const receiver_domain: u32 = std.math.maxInt(u32);

pub fn usesDomain(graph: *const g.GlobalSemanticGraph, methods: schema.Range(g.GlobalVirtualRegistryId), index: u32) bool {
    for (graph.virtual_registry_refs.items[methods.start..][0..methods.len]) |id| {
        const contract = graph.virtual_registries.items[@intFromEnum(id)].safety_contract orelse continue;
        for (contract.access_bounds) |bound| if (bound.domain_index == index) return true;
    }
    return false;
}

pub fn mappingProjections(a: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, concrete: g.GlobalTypeId, fields: []const u32) ![]const Projection {
    var ty = concrete;
    var projections: std.ArrayList(Projection) = .empty;
    errdefer projections.deinit(a);
    for (fields) |index| {
        var depth: usize = 0;
        while (graph.semanticType(ty) == .pointer) {
            if (depth == 128) return error.InvalidAccessRegion;
            depth += 1;
            try projections.append(a, .dereference);
            ty = graph.semanticType(ty).pointer.child;
        }
        const layout = types.fields(graph, ty) orelse return error.InvalidAccessRegion;
        if (index >= layout.len) return error.InvalidAccessRegion;
        try projections.append(a, .{ .field = index });
        ty = graph.fields.items[layout.start + index].ty;
    }
    return projections.toOwnedSlice(a);
}

pub fn storageType(graph: *const g.GlobalSemanticGraph, storage: @import("place.zig").PlaceFor(g.GlobalBindingId)) ?g.GlobalTypeId {
    if (@intFromEnum(storage.root) >= graph.bindings.items.len or graph.isBindingTypeUnresolved(storage.root)) return null;
    var ty = graph.binding(storage.root).ty;
    for (storage.projections) |projection| switch (projection) {
        .field => |index| {
            if (graph.semanticType(ty) == .pointer) ty = graph.semanticType(ty).pointer.child;
            if (types.arrayElement(graph, ty)) |element| {
                ty = element;
                continue;
            }
            const fields = types.fields(graph, ty) orelse return null;
            if (index >= fields.len) return null;
            ty = graph.fields.items[fields.start + index].ty;
        },
        .variant => |index| {
            const variants = types.variants(graph, ty) orelse return null;
            if (index >= variants.len) return null;
            ty = graph.variants.items[variants.start + index].payload_type orelse return null;
        },
        .static_index, .dynamic_index => ty = types.arrayElement(graph, ty) orelse return null,
        .dereference => ty = if (graph.semanticType(ty) == .pointer) graph.semanticType(ty).pointer.child else return null,
    };
    return ty;
}

/// Distinct logical places need not occupy disjoint storage. In particular,
/// union alternatives overlap even though their field identities stay distinct.
pub fn storageMayOverlap(graph: *const g.GlobalSemanticGraph, left: @import("place.zig").PlaceFor(g.GlobalBindingId), right: @TypeOf(left)) bool {
    if (left.mayOverlap(right)) return true;
    if (left.root != right.root) return false;
    const common = @min(left.projections.len, right.projections.len);
    for (left.projections[0..common], right.projections[0..common], 0..) |a, b, index| {
        if (a.eql(b)) continue;
        if (a != .field or b != .field) return false;
        const container = storageType(graph, .{ .root = left.root, .projections = left.projections[0..index] }) orelse return true;
        return types.isCUnion(graph, container);
    }
    return false;
}

pub fn selectedType(graph: *const g.GlobalSemanticGraph, function: g.Function, path: facts.InputPath) !struct { ty: g.GlobalTypeId, external: bool, mutable: bool } {
    if (path.input_index >= function.input.len) return error.InvalidAccessRegion;
    var ty = graph.fields.items[function.input.start + path.input_index].ty;
    var external = false;
    var mutable = false;
    if (graph.semanticType(ty) == .pointer) {
        const pointer = graph.semanticType(ty).pointer;
        ty = pointer.child;
        external = true;
        mutable = pointer.mutability == .read_write;
    }
    for (path.projections) |projection| switch (projection) {
        .field => |index| {
            const fields = types.fields(graph, ty) orelse return error.IndirectAccessDomainMapping;
            if (index >= fields.len) return error.InvalidAccessRegion;
            ty = graph.fields.items[fields.start + index].ty;
        },
        .dereference => {
            if (graph.semanticType(ty) != .pointer) return error.InvalidAccessRegion;
            const pointer = graph.semanticType(ty).pointer;
            ty = pointer.child;
            external = true;
            mutable = pointer.mutability == .read_write;
        },
        .static_index, .dynamic_index => ty = types.arrayElement(graph, ty) orelse return error.InvalidAccessRegion,
        .variant => |index| {
            const variants = types.variants(graph, ty) orelse return error.InvalidAccessRegion;
            if (index >= variants.len) return error.InvalidAccessRegion;
            ty = graph.variants.items[variants.start + index].payload_type orelse return error.InvalidAccessRegion;
        },
    };
    return .{ .ty = ty, .external = external, .mutable = mutable };
}

/// A reference-valued mapping denotes its referent; selecting it also reads
/// the reference slot. Virtual mappings denote only their erased receiver.
/// Neither form includes further reachable references or named captured regions.
pub fn region(a: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, function: g.Function, path: facts.InputPath, mode: facts.AccessMode) ![]const facts.InputAccess {
    const selected = try selectedType(graph, function, path);
    const ty = graph.semanticType(selected.ty);
    if (ty == .pointer) {
        if (mode == .write and ty.pointer.mutability != .read_write) return error.ReadonlyAccessDomain;
        var accesses: std.ArrayList(facts.InputAccess) = .empty;
        if (selected.external) try accesses.append(a, .{ .target = path, .mode = .read });
        var target = path;
        target.projections = try std.mem.concat(a, Projection, &.{ path.projections, &.{.dereference} });
        try accesses.append(a, .{ .target = target, .mode = mode });
        return accesses.toOwnedSlice(a);
    }
    if (ty == .virtual) {
        var accesses: std.ArrayList(facts.InputAccess) = .empty;
        // Locating the handle reads its slot. The operation's authority belongs
        // to the erased receiver, which can differ from that slot's storage.
        if (selected.external) try accesses.append(a, .{ .target = path, .mode = .read });
        var target = path;
        target.storage_domain = receiver_domain;
        try accesses.append(a, .{ .target = target, .mode = mode });
        return accesses.toOwnedSlice(a);
    }
    if (!selected.external) return &.{};
    if (mode == .write and !selected.mutable) return error.ReadonlyAccessDomain;
    return a.dupe(facts.InputAccess, &.{.{ .target = path, .mode = mode }});
}

pub fn resolveContract(a: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, function: g.Function, contract: *contracts.Contract, mappings: []const schema.StorageDomainMapping, receiver: ?u32) anyerror!void {
    var accesses: std.ArrayList(facts.InputAccess) = .empty;
    for (contract.access_bounds) |access| {
        const domain = access.target.storage_domain orelse {
            try accesses.append(a, access);
            continue;
        };
        if (receiver == null or access.target.input_index != receiver.?) return error.InvalidAccessDomainReceiver;
        // Locating a mapped resource may read the receiver representation.
        try accesses.append(a, .{ .target = .{ .input_index = receiver.? }, .mode = .read });
        var found = false;
        for (mappings) |mapping| if (mapping.domain_index == domain) {
            if (mapping.paths.len == 0) return error.MissingAccessDomain;
            found = true;
            for (mapping.paths) |path| {
                const input = graph.semanticType(graph.fields.items[function.input.start + receiver.?].ty);
                if (input != .pointer) return error.InvalidAccessDomainReceiver;
                const projections = try mappingProjections(a, graph, input.pointer.child, path.fields);
                for (projections, 0..) |projection, index| if (projection == .dereference) {
                    try accesses.append(a, .{ .target = .{ .input_index = receiver.?, .projections = projections[0 .. index + 1] }, .mode = .read });
                };
                if (path.nested_domain) |nested| {
                    var target = facts.InputPath{ .input_index = receiver.?, .projections = projections };
                    const selected = try selectedType(graph, function, target);
                    if (graph.semanticType(selected.ty) == .pointer) {
                        target.projections = try std.mem.concat(a, Projection, &.{ projections, &.{.dereference} });
                    }
                    if (graph.semanticType((try selectedType(graph, function, target)).ty) != .virtual) return error.InvalidAccessRegion;
                    try accesses.append(a, .{ .target = target, .mode = .read });
                    // Named operations may read the inner receiver to locate
                    // their region. They do not acquire its write authority.
                    try accesses.append(a, .{ .target = .{ .input_index = target.input_index, .projections = target.projections, .storage_domain = receiver_domain }, .mode = .read });
                    target.storage_domain = nested;
                    try accesses.append(a, .{ .target = target, .mode = access.mode });
                } else try accesses.appendSlice(a, try region(a, graph, function, .{ .input_index = receiver.?, .projections = projections }, access.mode));
            }
        };
        if (!found) return error.MissingAccessDomain;
    }
    contract.access_bounds = try accesses.toOwnedSlice(a);
    for (contract.outcomes) |outcome| try resolveContract(a, graph, function, @constCast(outcome.effects), mappings, receiver);
    for (contract.guarded_effects) |guard| try resolveContract(a, graph, function, @constCast(guard.effects), mappings, receiver);
}

test "mapped access domains cover their referents without permitting unrelated writes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source: schema.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } },
        .{ .pointer = .{ .child = @enumFromInt(2), .mutability = .read_only } },
    });
    for ([_]g.GlobalTypeId{ @enumFromInt(1), @enumFromInt(1), @enumFromInt(3) }) |ty|
        try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = ty, .source = source });
    const function: g.Function = .{ .declaration = @enumFromInt(0), .input = .{ .start = 2, .len = 1 }, .output = .{ .start = 0, .len = 0 } };
    const declared: contracts.Contract = .{ .outputs = &.{}, .bounded_access = true, .access_bounds = &.{.{ .target = .{ .input_index = 0, .storage_domain = 0 }, .mode = .write }} };
    var allowed = declared;
    try resolveContract(a, &graph, function, &allowed, &.{.{ .domain_index = 0, .paths = &.{.{ .fields = &.{0} }} }}, 0);
    try std.testing.expect((try contracts.check(a, allowed, .{ .input_accesses = &.{
        .{ .target = .{ .input_index = 0 }, .mode = .read },
        .{ .target = .{ .input_index = 0, .projections = &.{ .{ .field = 0 }, .dereference } }, .mode = .write },
    } })) == null);
    try std.testing.expectEqual(contracts.Failure.Kind.undeclared_access, (try contracts.check(a, allowed, .{ .input_accesses = &.{.{ .target = .{ .input_index = 0 }, .mode = .write }} })).?.kind);
    try std.testing.expectEqual(contracts.Failure.Kind.undeclared_access, (try contracts.check(a, allowed, .{ .input_accesses = &.{.{ .target = .{ .input_index = 0, .projections = &.{ .{ .field = 1 }, .dereference } }, .mode = .write }} })).?.kind);
    graph.types.items[1].pointer.mutability = .read_only;
    allowed = declared;
    try std.testing.expectError(error.ReadonlyAccessDomain, resolveContract(a, &graph, function, &allowed, &.{.{ .domain_index = 0, .paths = &.{.{ .fields = &.{0} }} }}, 0));
}

test "intermediate access mappings preserve traversal and final reference authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source: schema.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } },
        .{ .pointer = .{ .child = @enumFromInt(2), .mutability = .read_only } },
        .{ .structural = .{ .fields = .{ .start = 2, .len = 1 } } },
        .{ .pointer = .{ .child = @enumFromInt(4), .mutability = .read_only } },
    });
    for ([_]g.GlobalTypeId{ @enumFromInt(1), @enumFromInt(1), @enumFromInt(3), @enumFromInt(5) }) |ty|
        try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = ty, .source = source });
    const function: g.Function = .{ .declaration = @enumFromInt(0), .input = .{ .start = 3, .len = 1 }, .output = .{ .start = 0, .len = 0 } };
    const declared: contracts.Contract = .{ .outputs = &.{}, .bounded_access = true, .access_bounds = &.{.{ .target = .{ .input_index = 0, .storage_domain = 0 }, .mode = .write }} };
    const mappings: []const schema.StorageDomainMapping = &.{.{ .domain_index = 0, .paths = &.{.{ .fields = &.{ 0, 0 } }} }};
    var allowed = declared;
    try resolveContract(a, &graph, function, &allowed, mappings, 0);
    const target: facts.InputPath = .{ .input_index = 0, .projections = &.{ .{ .field = 0 }, .dereference, .{ .field = 0 }, .dereference } };
    try std.testing.expect((try contracts.check(a, allowed, .{ .input_accesses = &.{
        .{ .target = .{ .input_index = 0, .projections = &.{ .{ .field = 0 }, .dereference } }, .mode = .read },
        .{ .target = target, .mode = .write },
    } })) == null);
    try std.testing.expectEqual(contracts.Failure.Kind.undeclared_access, (try contracts.check(a, allowed, .{ .input_accesses = &.{.{
        .target = .{ .input_index = 0, .projections = &.{ .{ .field = 0 }, .dereference, .{ .field = 1 }, .dereference } },
        .mode = .read,
    }} })).?.kind);
    graph.fields.items[0].ty = @enumFromInt(0);
    allowed = declared;
    try std.testing.expectError(error.ReadonlyAccessDomain, resolveContract(a, &graph, function, &allowed, mappings, 0));
}

pub fn description(err: anyerror) []const u8 {
    return switch (err) {
        error.ReadonlyAccessDomain => "writes requires mutable storage or a mutable reference in its access domain mapping",
        error.IndirectAccessDomainMapping => "access domain mapping does not identify a valid structural field",
        error.InvalidAccessDomainReceiver => "access domains must select the participant receiver",
        else => "access domain has no valid concrete storage mapping",
    };
}

test "storage overlap respects union layout without merging field identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source: schema.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 }, .layout = .c_union } },
        .{ .structural = .{ .fields = .{ .start = 2, .len = 1 } } },
    });
    for ([_]g.GlobalTypeId{ @enumFromInt(0), @enumFromInt(0), @enumFromInt(2) }) |ty|
        try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = ty, .source = source });
    for ([_]g.GlobalTypeId{ @enumFromInt(1), @enumFromInt(2), @enumFromInt(3) }) |ty|
        try graph.bindings.append(a, .{ .name = .{ .start = 0, .len = 0 }, .source = source, .ty = ty, .mutability = .variable });
    const P = @import("place.zig").PlaceFor(g.GlobalBindingId);
    const record_first: P = .{ .root = @enumFromInt(0), .projections = &.{.{ .field = 0 }} };
    const record_second: P = .{ .root = @enumFromInt(0), .projections = &.{.{ .field = 1 }} };
    const union_first: P = .{ .root = @enumFromInt(1), .projections = record_first.projections };
    const union_second: P = .{ .root = @enumFromInt(1), .projections = record_second.projections };
    try std.testing.expect(!storageMayOverlap(&graph, record_first, record_second));
    try std.testing.expect(!union_first.eql(union_second));
    try std.testing.expect(storageMayOverlap(&graph, union_first, union_second));
    try std.testing.expect(storageMayOverlap(&graph, union_second, union_first));
    try std.testing.expect(!storageMayOverlap(&graph, record_first, union_first));
    try std.testing.expect(storageMayOverlap(&graph, .{ .root = @enumFromInt(2), .projections = &.{ .{ .field = 0 }, .{ .field = 0 } } }, .{ .root = @enumFromInt(2), .projections = &.{ .{ .field = 0 }, .{ .field = 1 } } }));
}
