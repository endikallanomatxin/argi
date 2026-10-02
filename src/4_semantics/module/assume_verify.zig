const std = @import("std");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");
const source_db = @import("../../1_base/source_db.zig");
const syn = @import("../../3_syntax/syntax_tree.zig");

/// Assumptions select lexical variables, so unknown names can be diagnosed
/// before lowering consumes their binding identities and discards the statement.
pub fn validate(allocator: std.mem.Allocator, files: []const syn.FileSyntaxTree, db: *const source_db.SourceDb, diagnostics: *diagnostics_mod.Diagnostics) !void {
    for (files) |*file| {
        var context = Context{ .allocator = allocator, .file = file, .db = db, .diagnostics = diagnostics };
        defer context.names.deinit(allocator);
        for (file.roots) |root| {
            if (file.tag(root) == .assume_statement) {
                try diagnostics.add(file.location(root), .semantic, "assume must appear inside a function", .{});
                continue;
            }
            const function = if (file.testDeclaration(root)) |test_decl| test_decl.function else file.functionDeclaration(root) orelse continue;
            context.names.clearRetainingCapacity();
            for ([_]syn.NodeIndex{ function.input, function.output }) |interface| {
                const literal = file.structTypeLiteral(interface) orelse continue;
                for (literal.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse continue;
                    try context.names.append(allocator, file.tokenText(db, field.name_token));
                }
            }
            if (function.body) |body| try context.walk(body);
        }
    }
}

const Context = struct {
    allocator: std.mem.Allocator,
    file: *const syn.FileSyntaxTree,
    db: *const source_db.SourceDb,
    diagnostics: *diagnostics_mod.Diagnostics,
    names: std.ArrayList([]const u8) = .empty,

    fn walk(self: *Context, node: syn.NodeIndex) anyerror!void {
        if (self.file.codeBlock(node)) |block| {
            const mark = self.names.items.len;
            defer self.names.shrinkRetainingCapacity(mark);
            for (block.statements) |statement| try self.walk(statement);
        } else if (self.file.symbolDeclaration(node)) |declaration| {
            try self.names.append(self.allocator, self.file.tokenText(self.db, declaration.name_token));
        } else if (self.file.tag(node) == .assume_statement) {
            if (self.file.assumedDeclaration(node)) |declaration| try self.walk(declaration);
            const name = self.file.tokenText(self.db, self.file.mainToken(node));
            for (self.names.items) |visible| if (std.mem.eql(u8, name, visible)) return;
            try self.diagnostics.add(self.file.location(node), .semantic, "assume requires an existing variable; '{s}' is not declared in this scope", .{name});
        } else if (self.file.ifStatement(node)) |statement| {
            try self.walk(statement.then_block);
            if (statement.else_block) |child| try self.walk(child);
        } else if (self.file.whileStatement(node)) |statement| {
            try self.walk(statement.body);
        } else if (self.file.forStatement(node)) |statement| {
            const mark = self.names.items.len;
            defer self.names.shrinkRetainingCapacity(mark);
            try self.names.append(self.allocator, self.file.tokenText(self.db, statement.name_token));
            try self.walk(statement.body);
        } else if (self.file.matchStatement(node)) |statement| {
            for (statement.cases) |case_node| {
                const case = self.file.matchCase(case_node).?;
                const mark = self.names.items.len;
                defer self.names.shrinkRetainingCapacity(mark);
                if (case.payload_name) |name| try self.names.append(self.allocator, self.file.tokenText(self.db, name));
                try self.walk(case.body);
            }
        }
    }
};
