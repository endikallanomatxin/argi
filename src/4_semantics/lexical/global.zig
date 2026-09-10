const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");
const file_bindings = @import("file_bindings.zig");
const semantic_strings = @import("../primitives/strings.zig");

pub const ScopeId = enum(u32) { none = std.math.maxInt(u32), _ };
pub const BindingId = enum(u32) { external = std.math.maxInt(u32), _ };
pub const ReferenceId = enum(u32) { _ };
pub const StringRange = semantic_strings.StringRange;
pub const SyntaxBridge = struct { file_index: u32, syntax_node: syn.NodeIndex };
pub const Scope = struct { parent: ScopeId, syntax: SyntaxBridge };
pub const Binding = struct { name: StringRange, scope: ScopeId, syntax: SyntaxBridge, source_offset: u32, kind: file_bindings.BindingKind };
pub const Reference = struct { name: StringRange, scope: ScopeId, binding: BindingId, syntax: SyntaxBridge, source_offset: u32, kind: file_bindings.ReferenceKind };
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

/// Compact lexical tables used first with module-local identities and then
/// relocated once at the real module-to-global boundary.
pub const LexicalTables = struct {
    scopes: std.ArrayList(Scope) = .empty,
    bindings: std.ArrayList(Binding) = .empty,
    references: std.ArrayList(Reference) = .empty,
    deferred_nodes: std.ArrayList(DeferredNode) = .empty,
    file_offsets: std.ArrayList(FileOffsets) = .empty,

    pub fn deinit(self: *LexicalTables, allocator: std.mem.Allocator) void {
        self.scopes.deinit(allocator);
        self.bindings.deinit(allocator);
        self.references.deinit(allocator);
        self.deferred_nodes.deinit(allocator);
        self.file_offsets.deinit(allocator);
        self.* = .{};
    }

    pub fn storageBytes(self: *const LexicalTables) usize {
        return self.scopes.items.len * @sizeOf(Scope) + self.bindings.items.len * @sizeOf(Binding) +
            self.references.items.len * @sizeOf(Reference) + self.deferred_nodes.items.len * @sizeOf(DeferredNode) +
            self.file_offsets.items.len * @sizeOf(FileOffsets);
    }

    pub fn appendFileBindings(self: *LexicalTables, allocator: std.mem.Allocator, strings: []const u8, local: *const file_bindings.FileBindings, file_index: u32) !void {
        const scope_base: u32 = @intCast(self.scopes.items.len);
        const binding_base: u32 = @intCast(self.bindings.items.len);
        try self.ensureCapacity(allocator, local.scopes.items.len, local.bindings.items.len, local.references.items.len, local.deferred_nodes.items.len, 1);
        for (local.scopes.items, 0..) |scope, index| {
            if (scope.parent != .none and @intFromEnum(scope.parent) >= index) return error.InvalidFileLexicalScope;
            self.scopes.appendAssumeCapacity(.{ .parent = relocateScope(scope.parent, scope_base), .syntax = .{ .file_index = file_index, .syntax_node = scope.syntax_node } });
        }
        for (local.bindings.items) |binding| {
            try validateName(strings, binding.name);
            self.bindings.appendAssumeCapacity(.{ .name = binding.name, .scope = relocateScope(binding.scope, scope_base), .syntax = .{ .file_index = file_index, .syntax_node = binding.syntax_node }, .source_offset = binding.source_offset, .kind = binding.kind });
        }
        for (local.references.items) |reference| {
            try validateName(strings, reference.name);
            self.references.appendAssumeCapacity(.{ .name = reference.name, .scope = relocateScope(reference.scope, scope_base), .binding = relocateBinding(reference.binding, binding_base), .syntax = .{ .file_index = file_index, .syntax_node = reference.syntax_node }, .source_offset = reference.source_offset, .kind = reference.kind });
        }
        for (local.deferred_nodes.items) |node| self.deferred_nodes.appendAssumeCapacity(.{ .file_index = file_index, .syntax_node = node });
        self.file_offsets.appendAssumeCapacity(offsetsFor(local, scope_base, binding_base, @intCast(self.references.items.len - local.references.items.len), @intCast(self.deferred_nodes.items.len - local.deferred_nodes.items.len)));
    }

    pub fn appendModule(self: *LexicalTables, allocator: std.mem.Allocator, strings: []const u8, module: *const LexicalTables, source_file_indices: []const u32, string_base: u32) !void {
        const scope_base: u32 = @intCast(self.scopes.items.len);
        const binding_base: u32 = @intCast(self.bindings.items.len);
        const reference_base: u32 = @intCast(self.references.items.len);
        const deferred_base: u32 = @intCast(self.deferred_nodes.items.len);
        try self.ensureCapacity(allocator, module.scopes.items.len, module.bindings.items.len, module.references.items.len, module.deferred_nodes.items.len, module.file_offsets.items.len);
        for (module.scopes.items) |scope| self.scopes.appendAssumeCapacity(.{ .parent = relocateSemanticScope(scope.parent, scope_base), .syntax = globalSyntax(scope.syntax, source_file_indices) });
        for (module.bindings.items) |binding| {
            try validateName(strings, binding.name);
            self.bindings.appendAssumeCapacity(.{ .name = relocateName(binding.name, string_base), .scope = relocateSemanticScope(binding.scope, scope_base), .syntax = globalSyntax(binding.syntax, source_file_indices), .source_offset = binding.source_offset, .kind = binding.kind });
        }
        for (module.references.items) |reference| {
            try validateName(strings, reference.name);
            self.references.appendAssumeCapacity(.{ .name = relocateName(reference.name, string_base), .scope = relocateSemanticScope(reference.scope, scope_base), .binding = relocateSemanticBinding(reference.binding, binding_base), .syntax = globalSyntax(reference.syntax, source_file_indices), .source_offset = reference.source_offset, .kind = reference.kind });
        }
        for (module.deferred_nodes.items) |node| self.deferred_nodes.appendAssumeCapacity(globalSyntax(node, source_file_indices));
        for (module.file_offsets.items) |offsets| self.file_offsets.appendAssumeCapacity(.{
            .scope_base = scope_base + offsets.scope_base,
            .scope_count = offsets.scope_count,
            .binding_base = binding_base + offsets.binding_base,
            .binding_count = offsets.binding_count,
            .reference_base = reference_base + offsets.reference_base,
            .reference_count = offsets.reference_count,
            .deferred_node_base = deferred_base + offsets.deferred_node_base,
            .deferred_node_count = offsets.deferred_node_count,
        });
    }

    fn ensureCapacity(self: *LexicalTables, allocator: std.mem.Allocator, scopes: usize, bindings: usize, references: usize, deferred: usize, files: usize) !void {
        try self.scopes.ensureUnusedCapacity(allocator, scopes);
        try self.bindings.ensureUnusedCapacity(allocator, bindings);
        try self.references.ensureUnusedCapacity(allocator, references);
        try self.deferred_nodes.ensureUnusedCapacity(allocator, deferred);
        try self.file_offsets.ensureUnusedCapacity(allocator, files);
    }
};

fn offsetsFor(local: *const file_bindings.FileBindings, scope_base: u32, binding_base: u32, reference_base: u32, deferred_base: u32) FileOffsets {
    return .{ .scope_base = scope_base, .scope_count = @intCast(local.scopes.items.len), .binding_base = binding_base, .binding_count = @intCast(local.bindings.items.len), .reference_base = reference_base, .reference_count = @intCast(local.references.items.len), .deferred_node_base = deferred_base, .deferred_node_count = @intCast(local.deferred_nodes.items.len) };
}
fn validateName(strings: []const u8, name: StringRange) !void {
    if (name.start > strings.len or name.len > strings.len - name.start) return error.InvalidLexicalName;
}
fn relocateScope(id: file_bindings.ScopeId, base: u32) ScopeId {
    return if (id == .none) .none else @enumFromInt(base + @intFromEnum(id));
}
fn relocateBinding(id: file_bindings.BindingId, base: u32) BindingId {
    return if (id == .external) .external else @enumFromInt(base + @intFromEnum(id));
}
fn relocateSemanticScope(id: ScopeId, base: u32) ScopeId {
    return if (id == .none) .none else @enumFromInt(base + @intFromEnum(id));
}
fn relocateSemanticBinding(id: BindingId, base: u32) BindingId {
    return if (id == .external) .external else @enumFromInt(base + @intFromEnum(id));
}
fn relocateName(name: StringRange, base: u32) StringRange {
    return .{ .start = base + name.start, .len = name.len };
}

fn globalSyntax(syntax: SyntaxBridge, source_file_indices: []const u32) SyntaxBridge {
    return .{ .file_index = source_file_indices[syntax.file_index], .syntax_node = syntax.syntax_node };
}
