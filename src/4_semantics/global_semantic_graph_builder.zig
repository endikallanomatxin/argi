const std = @import("std");
const file_sema = @import("file_semantic_graph.zig");
const syn = @import("../3_syntax/syntax_tree.zig");

pub const GlobalDeclId = enum(u32) { _ };
/// Relocated lookup identity; this is not a resolved canonical GlobalTypeId.
pub const GlobalTypeRefId = enum(u32) { _ };

pub const FileOffsets = struct {
    declaration_base: u32,
    declaration_count: u32,
    string_base: u32,
    type_reference_base: u32,
    type_reference_count: u32,
};

pub const Declaration = struct {
    kind: file_sema.DeclarationKind,
    name: file_sema.StringRange,
    source_offset: u32,
    file_index: u32,
    syntax_node: syn.NodeIndex,
};

/// Provisional storage for globalization, not a persistent frontend artifact or
/// the finalized GlobalSemanticGraph consumed by Safety and Codegen. Mechanical
/// merging populates these tables before global resolution selects their targets.
/// File ordinals and syntax nodes bridge consumers during expression lowering;
/// they must disappear from finalized global relationships as migration proceeds.
pub const GlobalSemanticGraphBuilder = struct {
    declarations: std.ArrayList(Declaration) = .empty,
    strings: std.ArrayList(u8) = .empty,
    file_offsets: std.ArrayList(FileOffsets) = .empty,
    type_references: std.ArrayList(file_sema.TypeReference) = .empty,

    pub fn deinit(self: *GlobalSemanticGraphBuilder, allocator: std.mem.Allocator) void {
        self.declarations.deinit(allocator);
        self.strings.deinit(allocator);
        self.file_offsets.deinit(allocator);
        self.type_references.deinit(allocator);
        self.* = .{};
    }

    pub fn globalDeclId(self: *const GlobalSemanticGraphBuilder, file_index: usize, local_id: file_sema.FileDeclId) GlobalDeclId {
        const offsets = self.file_offsets.items[file_index];
        const local_index = @intFromEnum(local_id);
        std.debug.assert(local_index < offsets.declaration_count);
        return @enumFromInt(offsets.declaration_base + local_index);
    }

    pub fn declaration(self: *const GlobalSemanticGraphBuilder, id: GlobalDeclId) Declaration {
        return self.declarations.items[@intFromEnum(id)];
    }

    pub fn text(self: *const GlobalSemanticGraphBuilder, range: file_sema.StringRange) []const u8 {
        return self.strings.items[range.start..][0..range.len];
    }

    pub fn storageBytes(self: *const GlobalSemanticGraphBuilder) usize {
        return self.declarations.items.len * @sizeOf(Declaration) +
            self.strings.items.len + self.file_offsets.items.len * @sizeOf(FileOffsets) +
            self.type_references.items.len * @sizeOf(file_sema.TypeReference);
    }

    pub fn globalTypeRefId(self: *const GlobalSemanticGraphBuilder, file_index: usize, local_id: file_sema.FileTypeRefId) GlobalTypeRefId {
        const offsets = self.file_offsets.items[file_index];
        std.debug.assert(@intFromEnum(local_id) < offsets.type_reference_count);
        return @enumFromInt(offsets.type_reference_base + @intFromEnum(local_id));
    }

    pub fn findTypeReference(self: *const GlobalSemanticGraphBuilder, file_index: usize, node: syn.NodeIndex) ?file_sema.TypeReference {
        const offsets = self.file_offsets.items[file_index];
        var start: usize = offsets.type_reference_base;
        var end = start + offsets.type_reference_count;
        while (start < end) {
            const middle = start + (end - start) / 2;
            const reference = self.type_references.items[middle];
            if (@intFromEnum(reference.syntax_node) < @intFromEnum(node)) {
                start = middle + 1;
            } else if (@intFromEnum(reference.syntax_node) > @intFromEnum(node)) {
                end = middle;
            } else return reference;
        }
        return null;
    }
};

pub fn mergeFileGraphs(allocator: std.mem.Allocator, files: []const file_sema.FileSemanticGraph) !GlobalSemanticGraphBuilder {
    const max_count = std.math.maxInt(u32);
    if (files.len > max_count) return error.GlobalSemanticGraphBuilderTooLarge;
    var declaration_count: usize = 0;
    var string_count: usize = 0;
    var type_reference_count: usize = 0;
    for (files) |file| {
        if (file.declarations.items.len > max_count - declaration_count or
            file.strings.items.len > max_count - string_count or
            file.type_references.items.len > max_count - type_reference_count)
            return error.GlobalSemanticGraphBuilderTooLarge;
        declaration_count += file.declarations.items.len;
        string_count += file.strings.items.len;
        type_reference_count += file.type_references.items.len;
    }

    var merged: GlobalSemanticGraphBuilder = .{};
    errdefer merged.deinit(allocator);
    try merged.declarations.ensureTotalCapacity(allocator, declaration_count);
    try merged.strings.ensureTotalCapacity(allocator, string_count);
    try merged.file_offsets.ensureTotalCapacity(allocator, files.len);
    try merged.type_references.ensureTotalCapacity(allocator, type_reference_count);
    for (files, 0..) |file, file_index| {
        const offsets: FileOffsets = .{
            .declaration_base = @intCast(merged.declarations.items.len),
            .declaration_count = @intCast(file.declarations.items.len),
            .string_base = @intCast(merged.strings.items.len),
            .type_reference_base = @intCast(merged.type_references.items.len),
            .type_reference_count = @intCast(file.type_references.items.len),
        };
        merged.file_offsets.appendAssumeCapacity(offsets);
        merged.strings.appendSliceAssumeCapacity(file.strings.items);
        for (file.declarations.items) |decl| {
            // Validate local ranges before relocation, avoiding both invalid
            // slices and overflowing additions for malformed artifacts.
            if (decl.name.start > file.strings.items.len or
                decl.name.len > file.strings.items.len - decl.name.start)
                return error.InvalidFileDeclarationName;
            merged.declarations.appendAssumeCapacity(.{
                .kind = decl.kind,
                .name = .{ .start = offsets.string_base + decl.name.start, .len = decl.name.len },
                .source_offset = decl.source_offset,
                .file_index = @intCast(file_index),
                .syntax_node = decl.syntax_node,
            });
        }
        var previous_node: ?syn.NodeIndex = null;
        for (file.type_references.items) |reference| {
            if (previous_node) |previous| {
                if (@intFromEnum(previous) >= @intFromEnum(reference.syntax_node)) return error.InvalidTypeReferenceOrder;
            }
            previous_node = reference.syntax_node;
            merged.type_references.appendAssumeCapacity(.{
                .name = try relocateTypeName(&file, reference.name, offsets.string_base),
                .qualifier = if (reference.qualifier) |qualifier| try relocateTypeName(&file, qualifier, offsets.string_base) else null,
                .source_offset = reference.source_offset,
                .syntax_node = reference.syntax_node,
            });
        }
    }
    return merged;
}

fn relocateTypeName(file: *const file_sema.FileSemanticGraph, name: file_sema.StringRange, base: u32) !file_sema.StringRange {
    if (name.start > file.strings.items.len or name.len > file.strings.items.len - name.start)
        return error.InvalidTypeReferenceName;
    return .{ .start = base + name.start, .len = name.len };
}

fn testFile(allocator: std.mem.Allocator, name: []const u8) !file_sema.FileSemanticGraph {
    var file: file_sema.FileSemanticGraph = .{};
    errdefer file.deinit(allocator);
    try file.strings.appendSlice(allocator, name);
    try file.declarations.append(allocator, .{
        .kind = .binding,
        .name = .{ .start = 0, .len = @intCast(name.len) },
        .source_offset = 42,
        .syntax_node = @enumFromInt(3),
    });
    return file;
}

test "merge relocates local declaration identities and owns names" {
    const allocator = std.testing.allocator;
    var files = [_]file_sema.FileSemanticGraph{
        try testFile(allocator, "first"),
        .{},
    };
    defer for (&files) |*file| file.deinit(allocator);
    files[1] = try testFile(allocator, "second");
    var merged = try mergeFileGraphs(allocator, &files);
    defer merged.deinit(allocator);
    for (&files) |*file| file.deinit(allocator);

    const first = merged.globalDeclId(0, @enumFromInt(0));
    const second = merged.globalDeclId(1, @enumFromInt(0));
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(first));
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(second));
    try std.testing.expectEqualStrings("first", merged.text(merged.declaration(first).name));
    try std.testing.expectEqualStrings("second", merged.text(merged.declaration(second).name));
    try std.testing.expectEqual(@as(u32, 1), merged.declaration(second).file_index);
    try std.testing.expectEqual(@as(u32, 42), merged.declaration(second).source_offset);
    try std.testing.expectEqual(@as(u32, 3), @intFromEnum(merged.declaration(second).syntax_node));
    try std.testing.expectEqual(@as(u32, 5), merged.file_offsets.items[1].string_base);
    try std.testing.expectEqual(2 * @sizeOf(Declaration) + 11 + 2 * @sizeOf(FileOffsets), merged.storageBytes());
}

test "merge accepts empty input and empty files" {
    const allocator = std.testing.allocator;
    var empty = try mergeFileGraphs(allocator, &.{});
    defer empty.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), empty.storageBytes());
    var file = try testFile(allocator, "name");
    defer file.deinit(allocator);
    var merged = try mergeFileGraphs(allocator, &.{ .{}, file, .{} });
    defer merged.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(merged.globalDeclId(1, @enumFromInt(0))));
    try std.testing.expectEqual(@as(u32, 1), merged.file_offsets.items[2].declaration_base);
}

fn testMergeAllocationFailures(allocator: std.mem.Allocator) !void {
    var file = try testFile(allocator, "name");
    defer file.deinit(allocator);
    var merged = try mergeFileGraphs(allocator, &.{ file, file });
    defer merged.deinit(allocator);
    try std.testing.expectEqualStrings("name", merged.text(merged.declarations.items[1].name));
}

test "merge releases allocations on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testMergeAllocationFailures, .{});
}

test "merge rejects invalid local string ranges" {
    const allocator = std.testing.allocator;
    var file = try testFile(allocator, "name");
    defer file.deinit(allocator);
    file.declarations.items[0].name = .{ .start = std.math.maxInt(u32), .len = 1 };
    try std.testing.expectError(error.InvalidFileDeclarationName, mergeFileGraphs(allocator, &.{file}));
}

test "merge relocates unresolved type references without selecting types" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testMergeTypeReferences, .{});
}

fn testMergeTypeReferences(allocator: std.mem.Allocator) !void {
    var file: file_sema.FileSemanticGraph = .{};
    defer file.deinit(allocator);
    try file.strings.appendSlice(allocator, "geometryPoint");
    try file.type_references.append(allocator, .{
        .name = .{ .start = 8, .len = 5 },
        .qualifier = .{ .start = 0, .len = 8 },
        .syntax_node = @enumFromInt(7),
        .source_offset = 42,
    });
    var merged = try mergeFileGraphs(allocator, &.{ file, .{}, file });
    defer merged.deinit(allocator);
    file.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(merged.globalTypeRefId(0, @enumFromInt(0))));
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(merged.globalTypeRefId(2, @enumFromInt(0))));
    try std.testing.expectEqual(null, merged.findTypeReference(1, @enumFromInt(7)));
    try std.testing.expectEqual(null, merged.findTypeReference(2, @enumFromInt(8)));
    const reference = merged.findTypeReference(2, @enumFromInt(7)).?;
    try std.testing.expectEqualStrings("Point", merged.text(reference.name));
    try std.testing.expectEqualStrings("geometry", merged.text(reference.qualifier.?));
    try std.testing.expectEqual(@as(u32, 21), reference.name.start);
    try std.testing.expectEqual(@as(u32, 42), reference.source_offset);
}

test "merge rejects invalid type reference qualifiers and ordering" {
    const allocator = std.testing.allocator;
    var file: file_sema.FileSemanticGraph = .{};
    defer file.deinit(allocator);
    try file.strings.appendSlice(allocator, "Type");
    const reference: file_sema.TypeReference = .{
        .name = .{ .start = 0, .len = 4 },
        .qualifier = .{ .start = 4, .len = 1 },
        .source_offset = 0,
        .syntax_node = @enumFromInt(0),
    };
    try file.type_references.append(allocator, reference);
    try std.testing.expectError(error.InvalidTypeReferenceName, mergeFileGraphs(allocator, &.{file}));
    file.type_references.items[0].qualifier = null;
    try file.type_references.append(allocator, file.type_references.items[0]);
    try std.testing.expectError(error.InvalidTypeReferenceOrder, mergeFileGraphs(allocator, &.{file}));
}
