const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");
const semantic_strings = @import("../primitives/strings.zig");
const Error = semantic_strings.Error || error{FileBindingsTooLarge};

pub const ScopeId = enum(u32) { none = std.math.maxInt(u32), _ };
pub const BindingId = enum(u32) { external = std.math.maxInt(u32), _ };
pub const ReferenceId = enum(u32) { _ };
pub const StringRange = semantic_strings.StringRange;
pub const BindingKind = enum(u8) { input, output, local, iteration, payload };
pub const ReferenceKind = enum(u8) { value, assignment, keep, call, module, type };
pub const Scope = struct { parent: ScopeId, syntax_node: syn.NodeIndex };
pub const Binding = struct {
    name: StringRange,
    scope: ScopeId,
    syntax_node: syn.NodeIndex,
    source_offset: u32,
    kind: BindingKind,
};

test "file bindings preserve initializer order and loop scope" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testLexicalBindings, .{});
}

fn testLexicalBindings(allocator: std.mem.Allocator) !void {
    var tree: syn.FileSyntaxTree = .{ .file_id = @enumFromInt(0) };
    defer tree.deinit(allocator);
    var tokens: syn.FileTokenList = .empty;
    try tokens.append(allocator, .{
        .content = .{ .identifier = .{ .start = 0, .len = 1 } },
        .location = .{ .file = @enumFromInt(0), .offset = 0 },
    });
    tree.tokens = tokens.slice();
    const token: syn.TokenIndex = @enumFromInt(0);
    const identifier = try tree.addNode(allocator, .{ .tag = .identifier, .main_token = token, .data = .{ .token = token } });
    const declaration_extra = try tree.addExtra(allocator, syn.FieldExtra{
        .type_node = .none,
        .default_value = identifier.optional(),
    });
    const declaration = try tree.addNode(allocator, .{ .tag = .symbol_declaration_variable, .main_token = token, .data = .{ .extra = declaration_extra } });
    const range = try tree.addNodeRange(allocator, &.{identifier});
    const body = try tree.addNode(allocator, .{ .tag = .code_block, .main_token = token, .data = .{ .extra_range = range } });
    const for_extra = try tree.addExtra(allocator, syn.ForExtra{ .name_token = token, .iterable = identifier, .body = body });
    const loop = try tree.addNode(allocator, .{ .tag = .for_value, .main_token = token, .data = .{ .extra = for_extra } });
    const captured_extra = try tree.addExtra(allocator, syn.MatchCaseExtra{ .payload_name = .init(token), .body = body });
    const captured_case = try tree.addNode(allocator, .{ .tag = .match_case_value, .main_token = token, .data = .{ .extra = captured_extra } });
    const plain_extra = try tree.addExtra(allocator, syn.MatchCaseExtra{ .payload_name = .none, .body = body });
    const plain_case = try tree.addNode(allocator, .{ .tag = .match_case_value, .main_token = token, .data = .{ .extra = plain_extra } });
    const cases = try tree.addNodeRange(allocator, &.{ captured_case, plain_case });
    const match_extra = try tree.addExtra(allocator, cases);
    const match_node = try tree.addNode(allocator, .{ .tag = .match_statement, .main_token = token, .data = .{ .node_and_extra = .{ .node = identifier, .extra = match_extra } } });
    var strings: std.ArrayList(u8) = .empty;
    defer strings.deinit(allocator);
    var builder: Builder = .{ .allocator = allocator, .tree = &tree, .source = "x", .strings = &strings };
    defer builder.deinit();
    defer builder.result.deinit(allocator);
    const parent = try builder.scope(.none, body);
    try builder.walk(parent, identifier);
    try builder.bind(parent, identifier, token, .input, null);
    const child = try builder.scope(parent, body);
    try builder.walk(child, declaration);
    try builder.walk(child, identifier);
    try builder.walk(child, loop);
    try builder.walk(child, identifier);
    try builder.walk(parent, identifier);
    try builder.walk(child, match_node);
    const references = builder.result.references.items;
    try std.testing.expectEqual(@as(usize, 10), references.len);
    try std.testing.expectEqual(BindingId.external, references[0].binding);
    try std.testing.expectEqual(@as(BindingId, @enumFromInt(0)), references[1].binding);
    try std.testing.expectEqual(@as(BindingId, @enumFromInt(1)), references[2].binding);
    try std.testing.expectEqual(@as(BindingId, @enumFromInt(1)), references[3].binding);
    try std.testing.expectEqual(@as(BindingId, @enumFromInt(2)), references[4].binding);
    try std.testing.expectEqual(@as(BindingId, @enumFromInt(1)), references[5].binding);
    try std.testing.expectEqual(@as(BindingId, @enumFromInt(0)), references[6].binding);
    try std.testing.expectEqual(@as(BindingId, @enumFromInt(1)), references[7].binding);
    try std.testing.expectEqual(@as(BindingId, @enumFromInt(3)), references[8].binding);
    try std.testing.expectEqual(@as(BindingId, @enumFromInt(1)), references[9].binding);
    const spelling = references[4].name;
    try std.testing.expectEqualStrings("x", strings.items[spelling.start..][0..spelling.len]);
}
pub const Reference = struct {
    name: StringRange,
    scope: ScopeId,
    binding: BindingId,
    syntax_node: syn.NodeIndex,
    source_offset: u32,
    kind: ReferenceKind,
};

/// Lexical identities only: a local reference says which declaration supplies
/// its name, never its type, value, availability, ownership or overload choice.
/// Unhandled constructs retain explicit syntax bridges in deferred_nodes.
/// Names index the owning ModuleSemanticGraph's string store. These tables retain
/// neither a separate string allocation nor source, tree or owner pointers.
pub const FileBindings = struct {
    scopes: std.ArrayList(Scope) = .empty,
    bindings: std.ArrayList(Binding) = .empty,
    references: std.ArrayList(Reference) = .empty,
    deferred_nodes: std.ArrayList(syn.NodeIndex) = .empty,

    pub fn deinit(self: *FileBindings, allocator: std.mem.Allocator) void {
        self.scopes.deinit(allocator);
        self.bindings.deinit(allocator);
        self.references.deinit(allocator);
        self.deferred_nodes.deinit(allocator);
        self.* = .{};
    }

    pub fn storageBytes(self: *const FileBindings) usize {
        return self.scopes.items.len * @sizeOf(Scope) +
            self.bindings.items.len * @sizeOf(Binding) +
            self.references.items.len * @sizeOf(Reference) +
            self.deferred_nodes.items.len * @sizeOf(syn.NodeIndex);
    }
};

pub fn build(allocator: std.mem.Allocator, tree: *const syn.FileSyntaxTree, source: []const u8, strings: *std.ArrayList(u8)) !FileBindings {
    const original_length = strings.items.len;
    errdefer strings.shrinkRetainingCapacity(original_length);
    var builder: Builder = .{ .allocator = allocator, .tree = tree, .source = source, .strings = strings };
    defer builder.deinit();
    errdefer builder.result.deinit(allocator);
    for (tree.roots) |node| {
        if (tree.functionDeclaration(node)) |function| {
            try builder.function(node, function);
        } else if (tree.testDeclaration(node)) |test_function| {
            try builder.function(node, test_function.function);
        }
    }
    return builder.result;
}

const Builder = struct {
    allocator: std.mem.Allocator,
    tree: *const syn.FileSyntaxTree,
    source: []const u8,
    result: FileBindings = .{},
    strings: *std.ArrayList(u8),
    // Borrow source spellings only while building. Per-scope maps avoid scanning
    // unrelated functions or closed sibling scopes for every reference.
    names: std.ArrayList(std.StringHashMapUnmanaged(BindingId)) = .empty,

    fn deinit(self: *Builder) void {
        for (self.names.items) |*names| names.deinit(self.allocator);
        self.names.deinit(self.allocator);
    }

    fn name(self: *Builder, value: []const u8) !StringRange {
        return semantic_strings.append(self.strings, self.allocator, value);
    }

    fn scope(self: *Builder, parent: ScopeId, node: syn.NodeIndex) !ScopeId {
        if (self.result.scopes.items.len >= std.math.maxInt(u32)) return error.FileBindingsTooLarge;
        const id: ScopeId = @enumFromInt(@as(u32, @intCast(self.result.scopes.items.len)));
        try self.names.append(self.allocator, .empty);
        try self.result.scopes.append(self.allocator, .{ .parent = parent, .syntax_node = node });
        return id;
    }

    fn bind(self: *Builder, current: ScopeId, node: syn.NodeIndex, token: syn.TokenIndex, kind: BindingKind, spelling: ?[]const u8) !void {
        const value = spelling orelse self.tree.tokenTextFromSource(self.source, token);
        if (std.mem.eql(u8, value, "_") and (kind == .iteration or kind == .payload)) return;
        if (self.result.bindings.items.len >= std.math.maxInt(u32)) return error.FileBindingsTooLarge;
        const id: BindingId = @enumFromInt(@as(u32, @intCast(self.result.bindings.items.len)));
        try self.result.bindings.append(self.allocator, .{
            .name = try self.name(value),
            .scope = current,
            .syntax_node = node,
            .source_offset = self.tree.tokenLocation(token).offset,
            .kind = kind,
        });
        try self.names.items[@intFromEnum(current)].put(self.allocator, value, id);
    }

    fn lookup(self: *const Builder, current: ScopeId, value: []const u8) BindingId {
        var ancestor = current;
        while (ancestor != .none) : (ancestor = self.result.scopes.items[@intFromEnum(ancestor)].parent) {
            if (self.names.items[@intFromEnum(ancestor)].get(value)) |id| return id;
        }
        return .external;
    }

    fn reference(self: *Builder, current: ScopeId, node: syn.NodeIndex, token: syn.TokenIndex, kind: ReferenceKind) !void {
        if (self.result.references.items.len >= std.math.maxInt(u32)) return error.FileBindingsTooLarge;
        const value = self.tree.tokenTextFromSource(self.source, token);
        const binding = switch (kind) {
            .value, .assignment, .keep => self.lookup(current, value),
            .call, .module, .type => .external,
        };
        try self.result.references.append(self.allocator, .{
            .name = try self.name(value),
            .scope = current,
            .binding = binding,
            .syntax_node = node,
            .source_offset = self.tree.tokenLocation(token).offset,
            .kind = kind,
        });
    }

    fn function(self: *Builder, node: syn.NodeIndex, declaration: syn.FunctionDeclaration) Error!void {
        // Generic values take precedence over runtime bindings in GlobalSema.
        // Until parameterized parameter identities are lowered here, retain the
        // complete parameterized rather than selecting a runtime binding by name.
        if (declaration.generic_params.len != 0 or declaration.generic_params_struct != null)
            return self.deferNode(node);
        const current = try self.scope(.none, node);
        try self.parameters(current, declaration.input, .input);
        try self.parameters(current, declaration.output, .output);
        if (declaration.body) |body| try self.walk(current, body);
    }

    fn parameters(self: *Builder, current: ScopeId, node: syn.NodeIndex, kind: BindingKind) Error!void {
        const fields = self.tree.structTypeLiteral(node) orelse return self.deferNode(node);
        for (fields.fields) |field_node| {
            const field = self.tree.structTypeField(field_node).?;
            if (field.type_node) |ty| try self.deferNode(ty);
            if (field.default_value) |value| try self.walk(current, value);
            try self.bind(current, field_node, field.name_token, kind, if (field.inferred_result) "result" else null);
        }
    }

    fn deferNode(self: *Builder, node: syn.NodeIndex) !void {
        try self.result.deferred_nodes.append(self.allocator, node);
    }

    fn statements(self: *Builder, current: ScopeId, body: syn.NodeIndex) Error!void {
        const block = self.tree.codeBlock(body) orelse return self.walk(current, body);
        for (block.statements) |statement| try self.walk(current, statement);
    }

    fn walk(self: *Builder, current: ScopeId, node: syn.NodeIndex) Error!void {
        const tree = self.tree;
        if (tree.binaryOperation(node)) |binary| {
            try self.walk(current, binary.lhs);
            try self.walk(current, binary.rhs);
            try self.deferNode(node);
            return;
        }
        if (tree.unaryOperand(node)) |operand| {
            try self.walk(current, operand);
            return;
        }
        switch (tree.tag(node)) {
            .identifier => try self.reference(current, node, tree.mainToken(node), .value),
            .assignment => {
                const assignment = tree.assignment(node).?;
                try self.reference(current, node, assignment.name_token, .assignment);
                try self.walk(current, assignment.value);
            },
            .keep_statement => try self.reference(current, node, tree.keepStatement(node).?.name_token, .keep),
            .symbol_declaration_constant, .symbol_declaration_variable => {
                const declaration = tree.symbolDeclaration(node).?;
                if (declaration.type_node) |ty| try self.deferNode(ty);
                if (declaration.value) |value| {
                    // An import introduces a module alias, not a value binding.
                    if (tree.tag(value) == .import_statement) return self.deferNode(node);
                    try self.walk(current, value);
                }
                try self.bind(current, node, declaration.name_token, .local, null);
            },
            .code_block => try self.statements(try self.scope(current, node), node),
            .if_statement => {
                const statement = tree.ifStatement(node).?;
                try self.walk(current, statement.condition);
                try self.walk(current, statement.then_block);
                if (statement.else_block) |otherwise| try self.walk(current, otherwise);
            },
            .while_statement => {
                const statement = tree.whileStatement(node).?;
                try self.walk(current, statement.condition);
                try self.walk(current, statement.body);
            },
            .for_value, .for_borrow, .for_mut_borrow => {
                const statement = tree.forStatement(node).?;
                try self.walk(current, statement.iterable);
                const child = try self.scope(current, node);
                try self.bind(child, node, statement.name_token, .iteration, null);
                try self.statements(child, statement.body);
            },
            .match_statement => {
                const statement = tree.matchStatement(node).?;
                try self.walk(current, statement.value);
                for (statement.cases) |case_node| {
                    const case = tree.matchCase(case_node).?;
                    const child = try self.scope(current, case_node);
                    if (case.payload_name) |capture| try self.bind(child, case_node, capture, .payload, null);
                    try self.statements(child, case.body);
                }
            },
            .function_call => {
                const call = tree.functionCall(node).?;
                try self.reference(current, node, call.callee_token, .call);
                if (call.module_qualifier) |qualifier| try self.reference(current, node, qualifier, .module);
                for (call.type_arguments) |argument| try self.deferNode(argument);
                if (call.type_arguments_struct) |arguments| try self.deferNode(arguments);
                try self.walk(current, call.input);
                try self.deferNode(node);
            },
            .struct_value_literal => for (tree.structValueLiteral(node).?.fields) |field| try self.walk(current, field),
            .struct_value_field, .positional_value_field => try self.walk(current, tree.valueField(node).?.value),
            .list_literal => for (tree.listLiteral(node).?.elements) |element| try self.walk(current, element),
            .struct_field_access => {
                const value = tree.structFieldAccess(node).?.value;
                // Module aliases take precedence over local values for x.field.
                // Another file can introduce such an alias, so even a known
                // local binding cannot settle the receiver's identity here.
                if (tree.tag(value) == .identifier) return self.deferNode(node);
                try self.walk(current, value);
                try self.deferNode(node);
            },
            .choice_payload_access => try self.walk(current, tree.choicePayloadAccess(node).?.value),
            .choice_literal, .choice_some_literal => if (tree.choiceLiteral(node).?.payload) |payload| {
                try self.walk(current, payload);
            },
            .return_statement => if (tree.returnStatement(node).?.value) |value| {
                try self.walk(current, value);
            },
            .literal, .pipe_placeholder, .break_statement, .continue_statement => {},
            // Nested functions may capture their surrounding environment;
            // reach paths, type syntax and declaration-only tags need global
            // context. Retaining them avoids inventing value references.
            else => try self.deferNode(node),
        }
    }
};
