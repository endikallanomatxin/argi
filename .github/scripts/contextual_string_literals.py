from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    assert old in text, f"missing anchor in {path}: {old[:120]!r}"
    p.write_text(text.replace(old, new, 1))


replace_once(
    'src/4_semantics/module/body_lowerer.zig',
    '''            .string_literal => blk: {
                const text = try self.writer.addString(self.tree.tokenTextFromSource(self.source, literal.token));
                break :blk try self.resolved(node, try self.builtin(.Any), .{ .string_literal = text });
            },
''',
    '''            .string_literal => blk: {
                const text = try self.writer.addString(self.tree.tokenTextFromSource(self.source, literal.token));
                break :blk try self.resolved(node, null, .{ .string_literal = text });
            },
''',
)

replace_once(
    'src/4_semantics/global/core.zig',
    '''            if (supplied) |node| {
                const actual = self.graph.nodes.items[@intFromEnum(node)].ty orelse return .deferred;
                if (self.graph.isTypeUnresolved(actual) or self.graph.isTypeUnresolved(expected.ty)) return .deferred;
                if (types.equal(self.graph, actual, expected.ty)) score += 4 else if (self.callTypesCompatible(actual, expected.ty)) score += 3 else if (types.isBuiltin(self.graph, expected.ty, .Any)) score += 1 else if (self.contextualLiteralFits(node, expected.ty)) score += 3 else return .no_match;
            } else if (expected.default_value == null) return .no_match;
''',
    '''            if (supplied) |node| {
                if (self.graph.isTypeUnresolved(expected.ty)) return .deferred;
                const supplied_node = self.graph.nodes.items[@intFromEnum(node)];
                if (supplied_node.ty) |actual| {
                    if (self.graph.isTypeUnresolved(actual)) return .deferred;
                    if (types.equal(self.graph, actual, expected.ty)) score += 4 else if (self.callTypesCompatible(actual, expected.ty)) score += 3 else if (types.isBuiltin(self.graph, expected.ty, .Any)) score += 1 else if (self.contextualLiteralFits(node, expected.ty)) score += 3 else return .no_match;
                } else switch (supplied_node.content) {
                    .string_literal => if (self.contextualLiteralFits(node, expected.ty)) score += 3 else return .no_match,
                    else => return .deferred,
                }
            } else if (expected.default_value == null) return .no_match;
''',
)

replace_once(
    'src/4_semantics/global/core.zig',
    '''            const actual = self.graph.nodes.items[@intFromEnum(supplied)].ty orelse return false;
            if (types.equal(self.graph, actual, expected.ty) or self.callTypesCompatible(actual, expected.ty) or
                self.contextualLiteralFits(supplied, expected.ty)) continue;
            return false;
''',
    '''            const supplied_node = self.graph.nodes.items[@intFromEnum(supplied)];
            if (supplied_node.ty) |actual| {
                if (types.equal(self.graph, actual, expected.ty) or self.callTypesCompatible(actual, expected.ty) or
                    self.contextualLiteralFits(supplied, expected.ty)) continue;
            } else if (self.contextualLiteralFits(supplied, expected.ty)) continue;
            return false;
''',
)

print('string literals carry contextual construction state as null, not Any')
