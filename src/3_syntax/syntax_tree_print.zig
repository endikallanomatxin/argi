const std = @import("std");
const source_db = @import("../1_base/source_db.zig");
const syn = @import("syntax_tree.zig");

pub fn printNode(tree: *const syn.SyntaxFile, db: *const source_db.SourceDb, node: syn.NodeIndex, level: usize) void {
    indent(level);
    std.debug.print("{s}", .{@tagName(tree.tag(node))});
    const token_text = tree.tokenText(db, tree.mainToken(node));
    if (token_text.len != 0 and token_text[0] != '\n') std.debug.print(" `{s}`", .{token_text});
    std.debug.print(" @{d}\n", .{tree.location(node).offset});

    if (tree.functionDeclaration(node)) |declaration| {
        printNode(tree, db, declaration.input, level + 1);
        printNode(tree, db, declaration.output, level + 1);
        if (declaration.body) |body| printNode(tree, db, body, level + 1);
        return;
    }
    if (tree.testDeclaration(node)) |declaration| {
        printNode(tree, db, declaration.function.input, level + 1);
        printNode(tree, db, declaration.function.output, level + 1);
        if (declaration.function.body) |body| printNode(tree, db, body, level + 1);
        return;
    }
    if (tree.structTypeLiteral(node)) |literal| return printNodes(tree, db, literal.fields, level + 1);
    if (tree.choiceTypeLiteral(node)) |literal| return printNodes(tree, db, literal.variants, level + 1);
    if (tree.structValueLiteral(node)) |literal| return printNodes(tree, db, literal.fields, level + 1);
    if (tree.listLiteral(node)) |literal| return printNodes(tree, db, literal.elements, level + 1);
    if (tree.codeBlock(node)) |block| return printNodes(tree, db, block.statements, level + 1);
    if (tree.ifStatement(node)) |statement| {
        printNode(tree, db, statement.condition, level + 1);
        printNode(tree, db, statement.then_block, level + 1);
        if (statement.else_block) |else_block| printNode(tree, db, else_block, level + 1);
        return;
    }
    if (tree.matchStatement(node)) |statement| {
        printNode(tree, db, statement.value, level + 1);
        printNodes(tree, db, statement.cases, level + 1);
        return;
    }
    if (tree.binaryOperation(node)) |operation| {
        printNode(tree, db, operation.lhs, level + 1);
        printNode(tree, db, operation.rhs, level + 1);
        return;
    }
    if (tree.unaryOperand(node)) |operand| printNode(tree, db, operand, level + 1);
}

fn printNodes(tree: *const syn.SyntaxFile, db: *const source_db.SourceDb, nodes: []const syn.NodeIndex, level: usize) void {
    for (nodes) |node| printNode(tree, db, node, level);
}

fn indent(level: usize) void {
    for (0..level) |_| std.debug.print("  ", .{});
}
