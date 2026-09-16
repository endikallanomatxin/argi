from pathlib import Path

core = Path("src/4_semantics/global/core.zig")
text = core.read_text()
start = text.index("    fn resolveComparison(")
end = text.index("    fn contextualizeChoiceOperand(", start)
replacement = r'''    fn resolveComparison(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !bool {
        const left = globalizer.globalNode(o, value.left);
        const right = globalizer.globalNode(o, value.right);

        // In equality tests a bare `..variant` denotes the choice tag, not a
        // value construction. Materialize that tag directly so payload-bearing
        // variants can participate in refinement without weakening normal
        // construction rules.
        if (value.operator == .equal or value.operator == .not_equal) {
            if (self.graph.nodes.items[@intFromEnum(left)].ty) |left_ty| {
                if (try self.materializeChoiceTagOperand(module_index, o, right, left_ty))
                    return self.patchChoiceTagComparison(o, value, left, right);
            }
            if (self.graph.nodes.items[@intFromEnum(right)].ty) |right_ty| {
                if (try self.materializeChoiceTagOperand(module_index, o, left, right_ty))
                    // Canonicalize choice-vs-tag comparisons for Safety and
                    // codegen regardless of source operand order.
                    return self.patchChoiceTagComparison(o, value, right, left);
            }
        }

        var left_ty = self.graph.nodes.items[@intFromEnum(left)].ty orelse return false;
        if (self.graph.nodes.items[@intFromEnum(right)].ty == null and
            self.contextualizeChoiceOperand(module_index, o, right, left_ty)) return false;
        var right_ty = self.graph.nodes.items[@intFromEnum(right)].ty orelse return false;
        self.coerceIntegerPair(left, &left_ty, right, &right_ty);
        const bool_ty = try self.builtin(.Bool);
        const target = globalizer.globalNode(o, value.node);
        const directly_comparable = self.isBuiltinComparable(left_ty, right_ty) or
            ((value.operator == .equal or value.operator == .not_equal) and self.isCEnumPair(left_ty, right_ty));
        if (directly_comparable) {
            self.graph.nodes.items[@intFromEnum(target)] = .{
                .source = self.graph.nodes.items[@intFromEnum(left)].source,
                .ty = bool_ty,
                .content = .{ .comparison = .{ .operator = value.operator, .left = left, .right = right } },
            };
            self.stats.operators += 1;
            return true;
        }
        const operator: callable.OperatorKind = switch (value.operator) {
            .equal => .equal,
            .not_equal => .not_equal,
            else => return false,
        };
        const function = self.resolveOperator(module_index, operator, &.{ left_ty, right_ty }) catch return false;
        const input = try self.makeCallInput(function, &.{ left, right });
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(left)].source,
            .ty = bool_ty,
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        self.stats.operators += 1;
        return true;
    }

    fn patchChoiceTagComparison(
        self: *Resolver,
        o: globalizer.Offsets,
        value: anytype,
        choice: global_sg.GlobalNodeId,
        tag: global_sg.GlobalNodeId,
    ) !bool {
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(choice)].source,
            .ty = try self.builtin(.Bool),
            .content = .{ .comparison = .{
                .operator = value.operator,
                .left = choice,
                .right = tag,
            } },
        };
        self.stats.operators += 1;
        return true;
    }

    fn materializeChoiceTagOperand(
        self: *Resolver,
        module_index: usize,
        o: globalizer.Offsets,
        node_id: global_sg.GlobalNodeId,
        choice_ty: global_sg.GlobalTypeId,
    ) !bool {
        if (types.variants(self.graph, choice_ty) == null) return false;
        const module = &self.modules[module_index];
        for (module.semantic.pending_operations.items) |pending| switch (pending) {
            .resolve_choice_literal => |choice| {
                if (globalizer.globalNode(o, choice.node) != node_id) continue;
                if (choice.payload != null) return false;
                const reference = module.semantic.external_refs.items[@intFromEnum(choice.option)];
                const hit = types.findVariant(self.graph, choice_ty, module.text(reference.name)) orelse return false;
                self.graph.nodes.items[@intFromEnum(node_id)] = .{
                    .source = .{
                        .file_index = o.file_base + reference.source.file_index,
                        .offset = reference.source.offset,
                    },
                    .ty = try self.builtin(.Int32),
                    .content = .{ .int_literal = hit.variant.value },
                };
                return true;
            },
            else => {},
        };
        return false;
    }

'''
text = text[:start] + replacement + text[end:]
core.write_text(text)

control = Path("src/4_semantics/global/control.zig")
text = control.read_text()
old = '''        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            if (std.mem.eql(u8, self.graph.text(field.name), "value")) choice_value = field.value;
            if (std.mem.eql(u8, self.graph.text(field.name), "variant")) tag_node = field.value;
        }
'''
new = '''        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |field, index| {
            if (index < literal.dispatch_prefix_positional_count) {
                if (index == 0) choice_value = field.value;
                if (index == 1) tag_node = field.value;
                continue;
            }
            if (std.mem.eql(u8, self.graph.text(field.name), "value")) choice_value = field.value;
            if (std.mem.eql(u8, self.graph.text(field.name), "variant")) tag_node = field.value;
        }
'''
if text.count(old) != 1:
    raise RuntimeError(f"control positional-is anchor changed: {text.count(old)}")
control.write_text(text.replace(old, new, 1))

Path(".git/semantic-refactor-message").write_text("Resolve bare choice variants as tag tests\n")
