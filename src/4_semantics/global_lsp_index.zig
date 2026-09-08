const std = @import("std");
const source_db = @import("../1_base/source_db.zig");
const graph_mod = @import("global_semantic_graph.zig");
const types = @import("global_semantic_types.zig");
const primitives = @import("semantic_primitives.zig");

pub const Target = union(enum) {
    function: graph_mod.GlobalFunctionId,
    binding: graph_mod.GlobalBindingId,
    declaration: graph_mod.GlobalDeclId,
    field: graph_mod.GlobalFieldId,
    variant: graph_mod.GlobalVariantId,
};

pub const Occurrence = struct {
    source: primitives.SourceRef,
    len: u32,
    target: Target,
    declaration: bool = false,
};

/// Cold editor index derived from the final semantic graph. It intentionally
/// stores semantic IDs rather than pointers or copied names; consumers resolve
/// display text through GlobalSemanticGraph only when needed.
pub const Index = struct {
    occurrences: std.ArrayList(Occurrence) = .empty,

    pub fn deinit(self: *Index, allocator: std.mem.Allocator) void {
        self.occurrences.deinit(allocator);
        self.* = .{};
    }

    pub fn build(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph) !Index {
        var result: Index = .{};
        errdefer result.deinit(allocator);

        for (graph.declarations.items, 0..) |declaration, raw| {
            const decl_id: graph_mod.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
            const target: Target = if (declaration.function_id) |function|
                .{ .function = function }
            else
                .{ .declaration = decl_id };
            try result.appendUnique(allocator, .{
                .source = declaration.source,
                .len = @intCast(graph.text(declaration.name).len),
                .target = target,
                .declaration = true,
            });
        }

        for (graph.bindings.items, 0..) |binding, raw| {
            try result.appendUnique(allocator, .{
                .source = binding.source,
                .len = @intCast(graph.text(binding.name).len),
                .target = .{ .binding = @enumFromInt(@as(u32, @intCast(raw))) },
                .declaration = true,
            });
        }

        for (graph.fields.items, 0..) |field, raw| {
            try result.appendUnique(allocator, .{
                .source = field.source,
                .len = @intCast(graph.text(field.name).len),
                .target = .{ .field = @enumFromInt(@as(u32, @intCast(raw))) },
                .declaration = true,
            });
        }

        for (graph.variants.items, 0..) |variant, raw| {
            try result.appendUnique(allocator, .{
                .source = variant.source,
                .len = @intCast(graph.text(variant.name).len),
                .target = .{ .variant = @enumFromInt(@as(u32, @intCast(raw))) },
                .declaration = true,
            });
        }

        for (graph.nodes.items) |node| switch (node.content) {
            .function_call => |call| {
                const function = graph.functions.items[@intFromEnum(call.callee)];
                const declaration = graph.declarations.items[@intFromEnum(function.declaration)];
                try result.appendUnique(allocator, .{
                    .source = node.source,
                    .len = @intCast(graph.text(declaration.name).len),
                    .target = .{ .function = call.callee },
                });
            },
            .binding_use => |binding_id| {
                const binding = graph.bindings.items[@intFromEnum(binding_id)];
                try result.appendUnique(allocator, .{
                    .source = node.source,
                    .len = @intCast(graph.text(binding.name).len),
                    .target = .{ .binding = binding_id },
                });
            },
            .declaration => |decl_id| {
                const declaration = graph.declarations.items[@intFromEnum(decl_id)];
                const target: Target = if (declaration.function_id) |function|
                    .{ .function = function }
                else
                    .{ .declaration = decl_id };
                try result.appendUnique(allocator, .{
                    .source = node.source,
                    .len = @intCast(graph.text(declaration.name).len),
                    .target = target,
                });
            },
            .type_initializer => |initializer| {
                const declaration = graph.declarations.items[@intFromEnum(initializer.type_decl)];
                try result.appendUnique(allocator, .{
                    .source = node.source,
                    .len = @intCast(graph.text(declaration.name).len),
                    .target = .{ .declaration = initializer.type_decl },
                });
            },
            .struct_field_access => |access| {
                const owner_ty = graph.nodes.items[@intFromEnum(access.value)].ty orelse continue;
                const fields = types.fields(graph, owner_ty) orelse continue;
                if (access.field_index >= fields.len) continue;
                const field_id: graph_mod.GlobalFieldId = @enumFromInt(fields.start + access.field_index);
                const field = graph.fields.items[@intFromEnum(field_id)];
                try result.appendUnique(allocator, .{
                    .source = node.source,
                    .len = @intCast(graph.text(field.name).len),
                    .target = .{ .field = field_id },
                });
            },
            .choice_payload_access => |access| {
                const choice_ty = graph.nodes.items[@intFromEnum(access.value)].ty orelse continue;
                const variants = types.variants(graph, choice_ty) orelse continue;
                const raw_variant = @intFromEnum(access.variant);
                if (raw_variant < variants.start or raw_variant >= variants.start + variants.len) continue;
                const variant = graph.variants.items[raw_variant];
                try result.appendUnique(allocator, .{
                    .source = node.source,
                    .len = @intCast(graph.text(variant.name).len),
                    .target = .{ .variant = access.variant },
                });
            },
            else => {},
        };

        std.mem.sort(Occurrence, result.occurrences.items, {}, lessOccurrence);
        return result;
    }

    pub fn occurrenceAt(
        self: *const Index,
        graph: *const graph_mod.GlobalSemanticGraph,
        db: *const source_db.SourceDb,
        path: []const u8,
        line: u32,
        character: u32,
    ) ?Occurrence {
        const file = db.findPath(path) orelse return null;
        const offset = offsetForPosition(db, file, line, character) orelse return null;
        var best: ?Occurrence = null;
        for (self.occurrences.items) |occurrence| {
            if (!sourcePathEquals(graph, occurrence.source, path)) continue;
            if (offset < occurrence.source.offset or offset >= occurrence.source.offset + occurrence.len) continue;
            if (best == null or occurrence.len < best.?.len or (occurrence.declaration and !best.?.declaration)) best = occurrence;
        }
        return best;
    }

    pub fn declarationOccurrence(self: *const Index, target: Target) ?Occurrence {
        for (self.occurrences.items) |occurrence|
            if (occurrence.declaration and targetsEqual(occurrence.target, target)) return occurrence;
        return null;
    }

    pub fn countReferences(self: *const Index, target: Target, include_declaration: bool) usize {
        var count: usize = 0;
        for (self.occurrences.items) |occurrence| {
            if (!targetsEqual(occurrence.target, target)) continue;
            if (!include_declaration and occurrence.declaration) continue;
            count += 1;
        }
        return count;
    }

    pub fn targetName(graph: *const graph_mod.GlobalSemanticGraph, target: Target) []const u8 {
        return switch (target) {
            .function => |id| blk: {
                const function = graph.functions.items[@intFromEnum(id)];
                break :blk graph.text(graph.declarations.items[@intFromEnum(function.declaration)].name);
            },
            .binding => |id| graph.text(graph.bindings.items[@intFromEnum(id)].name),
            .declaration => |id| graph.text(graph.declarations.items[@intFromEnum(id)].name),
            .field => |id| graph.text(graph.fields.items[@intFromEnum(id)].name),
            .variant => |id| graph.text(graph.variants.items[@intFromEnum(id)].name),
        };
    }

    pub fn targetType(graph: *const graph_mod.GlobalSemanticGraph, target: Target) ?graph_mod.GlobalTypeId {
        return switch (target) {
            .function => null,
            .binding => |id| graph.bindings.items[@intFromEnum(id)].ty,
            .declaration => |id| graph.declarations.items[@intFromEnum(id)].type_id,
            .field => |id| graph.fields.items[@intFromEnum(id)].ty,
            .variant => |id| graph.variants.items[@intFromEnum(id)].payload_type,
        };
    }

    fn appendUnique(self: *Index, allocator: std.mem.Allocator, value: Occurrence) !void {
        for (self.occurrences.items) |existing| {
            if (existing.source.file_index == value.source.file_index and
                existing.source.offset == value.source.offset and
                existing.len == value.len and
                existing.declaration == value.declaration and
                targetsEqual(existing.target, value.target)) return;
        }
        try self.occurrences.append(allocator, value);
    }
};

pub fn sourcePath(graph: *const graph_mod.GlobalSemanticGraph, source: primitives.SourceRef) ?[]const u8 {
    if (source.file_index >= graph.files.items.len) return null;
    return graph.text(graph.files.items[source.file_index].path);
}

pub fn sourcePathEquals(graph: *const graph_mod.GlobalSemanticGraph, source: primitives.SourceRef, path: []const u8) bool {
    const actual = sourcePath(graph, source) orelse return false;
    if (std.mem.eql(u8, actual, path)) return true;
    return std.mem.eql(u8, std.fs.path.basename(actual), std.fs.path.basename(path));
}

pub fn sourceFileId(graph: *const graph_mod.GlobalSemanticGraph, db: *const source_db.SourceDb, source: primitives.SourceRef) ?source_db.FileId {
    const path = sourcePath(graph, source) orelse return null;
    if (db.findPath(path)) |file| return file;
    for (db.files, 0..) |file, index| {
        if (std.mem.eql(u8, std.fs.path.basename(file.path), std.fs.path.basename(path))) return db.fileId(index);
    }
    return null;
}

pub fn offsetForPosition(db: *const source_db.SourceDb, file: source_db.FileId, line: u32, character: u32) ?u32 {
    const metadata = db.get(file);
    const line_index: usize = line;
    if (line_index >= metadata.line_starts.len) return null;
    const start = metadata.line_starts[line_index];
    const raw = @as(u64, start) + character;
    if (raw > metadata.source.len or raw > std.math.maxInt(u32)) return null;
    return @intCast(raw);
}

pub fn targetsEqual(a: Target, b: Target) bool {
    return switch (a) {
        .function => |value| switch (b) { .function => |other| value == other, else => false },
        .binding => |value| switch (b) { .binding => |other| value == other, else => false },
        .declaration => |value| switch (b) { .declaration => |other| value == other, else => false },
        .field => |value| switch (b) { .field => |other| value == other, else => false },
        .variant => |value| switch (b) { .variant => |other| value == other, else => false },
    };
}

fn lessOccurrence(_: void, a: Occurrence, b: Occurrence) bool {
    if (a.source.file_index != b.source.file_index) return a.source.file_index < b.source.file_index;
    if (a.source.offset != b.source.offset) return a.source.offset < b.source.offset;
    if (a.len != b.len) return a.len < b.len;
    return @intFromBool(a.declaration) > @intFromBool(b.declaration);
}

test "GlobalSG editor index keeps semantic identity in compact IDs" {
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(graph_mod.GlobalFunctionId));
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(graph_mod.GlobalBindingId));
    try std.testing.expect(@sizeOf(Occurrence) <= 24);
}
