const std = @import("std");
const file_sema = @import("file_semantic_graph.zig");
const syn = @import("../3_syntax/syntax_tree.zig");

pub const GlobalDeclId = enum(u32) { _ };

pub const FileOffsets = struct {
    declaration_base: u32,
    declaration_count: u32,
    string_base: u32,
};

pub const Declaration = struct {
    kind: file_sema.DeclarationKind,
    name: file_sema.StringRange,
    source_offset: u32,
    file_index: u32,
    syntax_node: syn.NodeIndex,
};

/// Mechanical concatenation of file declarations, not the final semantic graph.
/// File ordinals and syntax nodes remain a temporary bridge to expression
/// lowering. The merge owns its strings and relocates identities without making
/// decisions about visibility, imports, types, or overloads.
pub const MergedDeclarations = struct {
    declarations: std.ArrayList(Declaration) = .empty,
    strings: std.ArrayList(u8) = .empty,
    file_offsets: std.ArrayList(FileOffsets) = .empty,

    pub fn deinit(self: *MergedDeclarations, allocator: std.mem.Allocator) void {
        self.declarations.deinit(allocator);
        self.strings.deinit(allocator);
        self.file_offsets.deinit(allocator);
        self.* = .{};
    }

    pub fn globalDeclId(self: *const MergedDeclarations, file_index: usize, local_id: file_sema.FileDeclId) GlobalDeclId {
        const offsets = self.file_offsets.items[file_index];
        const local_index = @intFromEnum(local_id);
        std.debug.assert(local_index < offsets.declaration_count);
        return @enumFromInt(offsets.declaration_base + local_index);
    }

    pub fn declaration(self: *const MergedDeclarations, id: GlobalDeclId) Declaration {
        return self.declarations.items[@intFromEnum(id)];
    }

    pub fn text(self: *const MergedDeclarations, range: file_sema.StringRange) []const u8 {
        return self.strings.items[range.start..][0..range.len];
    }

    pub fn storageBytes(self: *const MergedDeclarations) usize {
        return self.declarations.items.len * @sizeOf(Declaration) +
            self.strings.items.len + self.file_offsets.items.len * @sizeOf(FileOffsets);
    }
};

pub fn mergeFileGraphs(allocator: std.mem.Allocator, files: []const file_sema.FileSemanticGraph) !MergedDeclarations {
    const max_count = std.math.maxInt(u32);
    if (files.len > max_count) return error.MergedDeclarationsTooLarge;
    var declaration_count: usize = 0;
    var string_count: usize = 0;
    for (files) |file| {
        if (file.declarations.items.len > max_count - declaration_count or
            file.strings.items.len > max_count - string_count)
            return error.MergedDeclarationsTooLarge;
        declaration_count += file.declarations.items.len;
        string_count += file.strings.items.len;
    }

    var merged: MergedDeclarations = .{};
    errdefer merged.deinit(allocator);
    try merged.declarations.ensureTotalCapacity(allocator, declaration_count);
    try merged.strings.ensureTotalCapacity(allocator, string_count);
    try merged.file_offsets.ensureTotalCapacity(allocator, files.len);
    for (files, 0..) |file, file_index| {
        const offsets: FileOffsets = .{
            .declaration_base = @intCast(merged.declarations.items.len),
            .declaration_count = @intCast(file.declarations.items.len),
            .string_base = @intCast(merged.strings.items.len),
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
    }
    return merged;
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
