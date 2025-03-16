const std = @import("std");

pub const ASTNode = struct {
    kind: Kind,
    value: []const u8,

    pub const Kind = enum {
        function,
        variable,
        literal,
        binary_op,
    };
};

pub const FuncDef = struct {
    name: []const u8,
    body: []ASTNode, // lista de sentencias
};

pub const VarDecl = struct {
    name: []const u8,
    value: ASTNode,
};

pub fn parse(tokens: []Token) !std.ArrayList(ASTNode) {
    var ast = std.ArrayList(ASTNode).init(std.heap.page_allocator);
    return ast;
}
