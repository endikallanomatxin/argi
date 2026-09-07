const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const file_bindings = @import("file_bindings.zig");
const file_sema = @import("file_semantic_graph.zig");

pub const GlobalScopeId = enum(u32) { none = std.math.maxInt(u32), _ };
pub const GlobalBindingId = enum(u32) { external = std.math.maxInt(u32), _ };
pub const GlobalReferenceId = enum(u32) { _ };
pub const StringRange = file_sema.StringRange;

/// Temporary ownership bridge for syntax-backed lexical work. The file ordinal
/// is explicit because syntax node identities are dense only within one file.
pub const SyntaxBridge = struct {
    file_index: u32,
    syntax_node: syn.NodeIndex,
};

pub const Scope = struct {
    parent: GlobalScopeId,
    syntax: SyntaxBridge,
};

pub const Binding = struct {
    name: StringRange,
    scope: GlobalScopeId,
    syntax: SyntaxBridge,
    source_offset: u32,
    kind: file_bindings.BindingKind,
};

pub const Reference = struct {
    name: StringRange,
    scope: GlobalScopeId,
    binding: GlobalBindingId,
    syntax: SyntaxBridge,
    source_offset: u32,
    kind: file_bindings.ReferenceKind,
};

pub const DeferredNode = SyntaxBridge;

pub const FileOffsets = struct {
    scope_base: u32,
    scope_count: u32,
    binding_base: u32,
    binding_count: u32,
    reference_base: u32,
    reference_count: u32,
    deferred_node_base: u32,
    deferred_node_count: u32,
};

/// Flattened lexical identities. Names refer to the global string pool owned by
/// the enclosing global builder; this type deliberately owns no string bytes.
pub const GlobalLexicalTables = struct {
    scopes: std.ArrayList(Scope) = .empty,
    bindings: std.ArrayList(Binding) = .empty,
    references: std.ArrayList(Reference) = .empty,
    deferred_nodes: std.ArrayList(DeferredNode) = .empty,
    file_offsets: std.ArrayList(FileOffsets) = .empty,

    pub fn deinit(self: *GlobalLexicalTables, allocator: std.mem.Allocator) void {
        self.scopes.deinit(allocator);
        self.bindings.deinit(allocator);
        self.references.deinit(allocator);
        self.deferred_nodes.deinit(allocator);
        self.file_offsets.deinit(allocator);
        self.* = .{};
    }

    pub fn storageBytes(self: *const GlobalLexicalTables) usize {
        return self.scopes.items.len * @sizeOf(Scope) +
            self.bindings.items.len * @sizeOf(Binding) +
            self.references.items.len * @sizeOf(Reference) +
            self.deferred_nodes.items.len * @sizeOf(DeferredNode) +
            self.file_offsets.items.len * @sizeOf(FileOffsets);
    }

    pub fn appendFile(
        self: *GlobalLexicalTables,
        allocator: std.mem.Allocator,
        file: *const file_sema.FileSemanticGraph,
        string_base: u32,
        file_index: u32,
    ) !void {
        const local = &file.lexical;
        const max_count: usize = std.math.maxInt(u32);
        if (file.strings.items.len > max_count - @as(usize, string_base) or
            !canAppendU32(self.scopes.items.len, local.scopes.items.len) or
            !canAppendU32(self.bindings.items.len, local.bindings.items.len) or
            !canAppendU32(self.references.items.len, local.references.items.len) or
            !canAppendU32(self.deferred_nodes.items.len, local.deferred_nodes.items.len))
            return error.GlobalLexicalTablesTooLarge;

        const scope_base: u32 = @intCast(self.scopes.items.len);
        const binding_base: u32 = @intCast(self.bindings.items.len);
        const offsets: FileOffsets = .{
            .scope_base = scope_base,
            .scope_count = @intCast(local.scopes.items.len),
            .binding_base = binding_base,
            .binding_count = @intCast(local.bindings.items.len),
            .reference_base = @intCast(self.references.items.len),
            .reference_count = @intCast(local.references.items.len),
            .deferred_node_base = @intCast(self.deferred_nodes.items.len),
            .deferred_node_count = @intCast(local.deferred_nodes.items.len),
        };

        for (local.scopes.items, 0..) |scope, scope_index|
            try validateParentScopeId(scope.parent, scope_index);
        for (local.bindings.items) |binding| {
            try validateOwnedScopeId(binding.scope, local.scopes.items.len);
            try validateName(file, binding.name);
        }
        for (local.references.items) |reference| {
            try validateOwnedScopeId(reference.scope, local.scopes.items.len);
            try validateBindingId(reference.binding, local.bindings.items.len);
            try validateName(file, reference.name);
        }

        try self.scopes.ensureUnusedCapacity(allocator, local.scopes.items.len);
        try self.bindings.ensureUnusedCapacity(allocator, local.bindings.items.len);
        try self.references.ensureUnusedCapacity(allocator, local.references.items.len);
        try self.deferred_nodes.ensureUnusedCapacity(allocator, local.deferred_nodes.items.len);
        try self.file_offsets.ensureUnusedCapacity(allocator, 1);

        const syntax_file = file_index;
        for (local.scopes.items) |scope| self.scopes.appendAssumeCapacity(.{
            .parent = relocateScopeId(scope.parent, scope_base),
            .syntax = .{ .file_index = syntax_file, .syntax_node = scope.syntax_node },
        });
        for (local.bindings.items) |binding| self.bindings.appendAssumeCapacity(.{
            .name = relocateName(binding.name, string_base),
            .scope = relocateScopeId(binding.scope, scope_base),
            .syntax = .{ .file_index = syntax_file, .syntax_node = binding.syntax_node },
            .source_offset = binding.source_offset,
            .kind = binding.kind,
        });
        for (local.references.items) |reference| self.references.appendAssumeCapacity(.{
            .name = relocateName(reference.name, string_base),
            .scope = relocateScopeId(reference.scope, scope_base),
            .binding = relocateBindingId(reference.binding, binding_base),
            .syntax = .{ .file_index = syntax_file, .syntax_node = reference.syntax_node },
            .source_offset = reference.source_offset,
            .kind = reference.kind,
        });
        for (local.deferred_nodes.items) |node| self.deferred_nodes.appendAssumeCapacity(.{
            .file_index = syntax_file,
            .syntax_node = node,
        });
        self.file_offsets.appendAssumeCapacity(offsets);
    }
};

fn canAppendU32(current: usize, additional: usize) bool {
    const maximum: usize = std.math.maxInt(u32);
    return current <= maximum and additional <= maximum - current;
}

fn validateParentScopeId(id: file_bindings.ScopeId, scope_index: usize) !void {
    if (id != .none and @intFromEnum(id) >= scope_index) return error.InvalidFileLexicalScope;
}

fn validateOwnedScopeId(id: file_bindings.ScopeId, count: usize) !void {
    if (id == .none or @intFromEnum(id) >= count) return error.InvalidFileLexicalScope;
}

fn validateBindingId(id: file_bindings.BindingId, count: usize) !void {
    if (id != .external and @intFromEnum(id) >= count) return error.InvalidFileLexicalBinding;
}

fn validateName(file: *const file_sema.FileSemanticGraph, name: StringRange) !void {
    if (name.start > file.strings.items.len or name.len > file.strings.items.len - name.start)
        return error.InvalidFileLexicalName;
}

fn relocateScopeId(id: file_bindings.ScopeId, base: u32) GlobalScopeId {
    return if (id == .none) .none else @enumFromInt(base + @intFromEnum(id));
}

fn relocateBindingId(id: file_bindings.BindingId, base: u32) GlobalBindingId {
    return if (id == .external) .external else @enumFromInt(base + @intFromEnum(id));
}

fn relocateName(name: StringRange, base: u32) StringRange {
    return .{ .start = base + name.start, .len = name.len };
}

fn appendTestFile(allocator: std.mem.Allocator, file: *file_sema.FileSemanticGraph, name: []const u8) !void {
    try file.strings.appendSlice(allocator, name);
    try file.lexical.scopes.append(allocator, .{ .parent = .none, .syntax_node = @enumFromInt(1) });
    try file.lexical.scopes.append(allocator, .{ .parent = @enumFromInt(0), .syntax_node = @enumFromInt(2) });
    try file.lexical.bindings.append(allocator, .{
        .name = .{ .start = 0, .len = @intCast(name.len) },
        .scope = @enumFromInt(0),
        .syntax_node = @enumFromInt(3),
        .source_offset = 4,
        .kind = .local,
    });
    try file.lexical.references.append(allocator, .{
        .name = .{ .start = 0, .len = @intCast(name.len) },
        .scope = @enumFromInt(1),
        .binding = @enumFromInt(0),
        .syntax_node = @enumFromInt(5),
        .source_offset = 6,
        .kind = .value,
    });
    try file.lexical.references.append(allocator, .{
        .name = .{ .start = 0, .len = @intCast(name.len) },
        .scope = @enumFromInt(0),
        .binding = .external,
        .syntax_node = @enumFromInt(7),
        .source_offset = 8,
        .kind = .call,
    });
    try file.lexical.deferred_nodes.append(allocator, @enumFromInt(9));
}

test "append relocates independent local lexical identities" {
    const allocator = std.testing.allocator;
    var first: file_sema.FileSemanticGraph = .{};
    defer first.deinit(allocator);
    var second: file_sema.FileSemanticGraph = .{};
    defer second.deinit(allocator);
    try appendTestFile(allocator, &first, "one");
    try appendTestFile(allocator, &second, "two");

    var global: GlobalLexicalTables = .{};
    defer global.deinit(allocator);
    try global.appendFile(allocator, &first, 10, 3);
    try global.appendFile(allocator, &second, 20, 7);

    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(global.bindings.items[0].scope));
    try std.testing.expectEqual(@as(u32, 2), @intFromEnum(global.bindings.items[1].scope));
    try std.testing.expectEqual(GlobalScopeId.none, global.scopes.items[2].parent);
    try std.testing.expectEqual(@as(u32, 2), @intFromEnum(global.scopes.items[3].parent));
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(global.references.items[0].scope));
    try std.testing.expectEqual(@as(u32, 3), @intFromEnum(global.references.items[2].scope));
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(global.references.items[0].binding));
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(global.references.items[2].binding));
    try std.testing.expectEqual(GlobalBindingId.external, global.references.items[3].binding);
    try std.testing.expectEqual(@as(u32, 10), global.bindings.items[0].name.start);
    try std.testing.expectEqual(@as(u32, 20), global.bindings.items[1].name.start);
    try std.testing.expectEqual(@as(u32, 7), global.deferred_nodes.items[1].file_index);
    try std.testing.expectEqual(@as(u32, 9), @intFromEnum(global.deferred_nodes.items[1].syntax_node));
}

fn testAppendAllocationFailures(allocator: std.mem.Allocator) !void {
    var file: file_sema.FileSemanticGraph = .{};
    defer file.deinit(allocator);
    try appendTestFile(allocator, &file, "name");
    var global: GlobalLexicalTables = .{};
    defer global.deinit(allocator);
    try global.appendFile(allocator, &file, 12, 4);
    try std.testing.expectEqual(@as(usize, 2), global.scopes.items.len);
}

test "append releases allocations on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testAppendAllocationFailures, .{});
}

test "append rejects malformed local identities and names" {
    const allocator = std.testing.allocator;
    var file: file_sema.FileSemanticGraph = .{};
    defer file.deinit(allocator);
    try appendTestFile(allocator, &file, "name");
    var global: GlobalLexicalTables = .{};
    defer global.deinit(allocator);

    file.lexical.scopes.items[1].parent = @enumFromInt(1);
    try std.testing.expectError(error.InvalidFileLexicalScope, global.appendFile(allocator, &file, 0, 0));
    file.lexical.scopes.items[1].parent = @enumFromInt(0);
    file.lexical.scopes.items[0].parent = @enumFromInt(1);
    try std.testing.expectError(error.InvalidFileLexicalScope, global.appendFile(allocator, &file, 0, 0));
    file.lexical.scopes.items[0].parent = .none;
    file.lexical.bindings.items[0].scope = .none;
    try std.testing.expectError(error.InvalidFileLexicalScope, global.appendFile(allocator, &file, 0, 0));
    file.lexical.bindings.items[0].scope = @enumFromInt(0);
    file.lexical.references.items[0].scope = .none;
    try std.testing.expectError(error.InvalidFileLexicalScope, global.appendFile(allocator, &file, 0, 0));
    file.lexical.references.items[0].scope = @enumFromInt(1);
    file.lexical.references.items[0].binding = @enumFromInt(1);
    try std.testing.expectError(error.InvalidFileLexicalBinding, global.appendFile(allocator, &file, 0, 0));
    file.lexical.references.items[0].binding = @enumFromInt(0);
    file.lexical.bindings.items[0].name = .{ .start = 4, .len = 1 };
    try std.testing.expectError(error.InvalidFileLexicalName, global.appendFile(allocator, &file, 0, 0));
    try std.testing.expectEqual(@as(usize, 0), global.scopes.items.len);
}

test "append rejects global string range overflow" {
    var file: file_sema.FileSemanticGraph = .{};
    defer file.deinit(std.testing.allocator);
    try file.strings.append(std.testing.allocator, 'x');
    var global: GlobalLexicalTables = .{};
    defer global.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.GlobalLexicalTablesTooLarge,
        global.appendFile(std.testing.allocator, &file, std.math.maxInt(u32), 0),
    );
}
