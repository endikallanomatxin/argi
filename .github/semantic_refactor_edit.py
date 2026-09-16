from pathlib import Path

syntaxer = Path("src/3_syntax/syntaxer.zig")
text = syntaxer.read_text()

old_rhs = r'''    fn parsePipeRhs(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        const prev_pipe_rhs = self.parsing_pipe_rhs;
        self.parsing_pipe_rhs = true;
        defer self.parsing_pipe_rhs = prev_pipe_rhs;
        return self.parsePrimary();
    }
'''
new_rhs = r'''    const PipePlaceholderAnalysis = struct {
        has_placeholder: bool = false,
        direct_shape: bool = false,
        first_placeholder: ?syn.TokenIndex = null,
        invalid_token: ?syn.TokenIndex = null,
    };

    fn mergePipePlaceholderAnalysis(result: *PipePlaceholderAnalysis, child: PipePlaceholderAnalysis) void {
        if (!result.has_placeholder and child.has_placeholder) result.first_placeholder = child.first_placeholder;
        result.has_placeholder = result.has_placeholder or child.has_placeholder;
        if (result.invalid_token == null) result.invalid_token = child.invalid_token;
    }

    fn invalidatePipePlaceholderAnalysis(self: *Syntaxer, result: *PipePlaceholderAnalysis, node: syn.NodeIndex) void {
        if (result.has_placeholder and result.invalid_token == null)
            result.invalid_token = self.file.mainToken(node);
        result.direct_shape = false;
    }

    fn analyzePipePlaceholder(self: *Syntaxer, node: syn.NodeIndex) PipePlaceholderAnalysis {
        return switch (self.file.tag(node)) {
            .pipe_placeholder => .{
                .has_placeholder = true,
                .direct_shape = true,
                .first_placeholder = self.file.mainToken(node),
            },

            // These are the deliberately supported placeholder expressions.
            // Chaining field/payload projections remains a direct shape because
            // lowering can substitute the piped value before applying them.
            .address_of, .address_of_mut => blk: {
                const child_node = self.file.unaryOperand(node).?;
                var result = self.analyzePipePlaceholder(child_node);
                if (result.has_placeholder and (result.invalid_token != null or !result.direct_shape))
                    self.invalidatePipePlaceholderAnalysis(&result, node);
                break :blk result;
            },
            .struct_field_access => blk: {
                const access = self.file.structFieldAccess(node).?;
                var result = self.analyzePipePlaceholder(access.value);
                if (result.has_placeholder and (result.invalid_token != null or !result.direct_shape))
                    self.invalidatePipePlaceholderAnalysis(&result, node);
                break :blk result;
            },
            .choice_payload_access => blk: {
                const access = self.file.choicePayloadAccess(node).?;
                var result = self.analyzePipePlaceholder(access.value);
                if (result.has_placeholder and (result.invalid_token != null or !result.direct_shape))
                    self.invalidatePipePlaceholderAnalysis(&result, node);
                break :blk result;
            },

            // Calls and aggregate literals are containers: placeholders inside
            // their values keep their validity, but the container itself is not
            // a direct placeholder shape that another operator may wrap.
            .function_call => blk: {
                const call = self.file.functionCall(node).?;
                var result = self.analyzePipePlaceholder(call.input);
                result.direct_shape = false;
                break :blk result;
            },
            .struct_value_literal => blk: {
                const literal = self.file.structValueLiteral(node).?;
                var result: PipePlaceholderAnalysis = .{};
                for (literal.fields) |field_node|
                    mergePipePlaceholderAnalysis(&result, self.analyzePipePlaceholder(field_node));
                result.direct_shape = false;
                break :blk result;
            },
            .struct_value_field, .positional_value_field => blk: {
                const field = self.file.valueField(node).?;
                var result = self.analyzePipePlaceholder(field.value);
                result.direct_shape = false;
                break :blk result;
            },
            .list_literal => blk: {
                const literal = self.file.listLiteral(node).?;
                var result: PipePlaceholderAnalysis = .{};
                for (literal.elements) |element|
                    mergePipePlaceholderAnalysis(&result, self.analyzePipePlaceholder(element));
                result.direct_shape = false;
                break :blk result;
            },
            .choice_literal, .choice_some_literal => blk: {
                const literal = self.file.choiceLiteral(node).?;
                var result: PipePlaceholderAnalysis = .{};
                if (literal.payload) |payload| result = self.analyzePipePlaceholder(payload);
                result.direct_shape = false;
                break :blk result;
            },

            // Composite operators are not substitution points. If a placeholder
            // appears anywhere under one, diagnose the first unsupported
            // operator rather than the placeholder itself.
            .pipe_expression,
            .unwrap_or,
            .unwrap_or_do,
            .binary_add,
            .binary_subtract,
            .binary_multiply,
            .binary_divide,
            .binary_modulo,
            .compare_equal,
            .compare_not_equal,
            .compare_less,
            .compare_greater,
            .compare_less_equal,
            .compare_greater_equal,
            .logical_and,
            .logical_or,
            .error_context,
            .index_access,
            => blk: {
                const op = self.file.binaryOperation(node).?;
                var result = self.analyzePipePlaceholder(op.lhs);
                mergePipePlaceholderAnalysis(&result, self.analyzePipePlaceholder(op.rhs));
                self.invalidatePipePlaceholderAnalysis(&result, node);
                break :blk result;
            },

            .move_expression,
            .error_propagation,
            .nullable_test,
            .dereference,
            => blk: {
                var result = self.analyzePipePlaceholder(self.file.unaryOperand(node).?);
                self.invalidatePipePlaceholderAnalysis(&result, node);
                break :blk result;
            },

            else => .{},
        };
    }

    fn parsePipeRhs(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        const prev_pipe_rhs = self.parsing_pipe_rhs;
        self.parsing_pipe_rhs = true;
        defer self.parsing_pipe_rhs = prev_pipe_rhs;
        return self.parsePrimary();
    }
'''
if text.count(old_rhs) != 1:
    raise RuntimeError(f"parsePipeRhs anchor changed: {text.count(old_rhs)}")
text = text.replace(old_rhs, new_rhs, 1)

old_pipe = r'''    fn parsePipeExpr(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        var lhs = try self.parsePrimary();

        while (self.tokenIs(.pipe)) {
            const pipe_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            self.advanceOne();
            self.skipNewLinesAndComments();
            const right = try self.parsePipeRhs();
            lhs = try self.addNode(.pipe_expression, pipe_token, .{ .node_and_node = .{ .first = lhs, .second = right } });
        }
        return lhs;
    }
'''
new_pipe = r'''    fn parsePipeExpr(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        var lhs = try self.parsePrimary();

        while (self.tokenIs(.pipe)) {
            const pipe_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            self.advanceOne();
            self.skipNewLinesAndComments();
            const right = try self.parsePipeRhs();
            const placeholder = self.analyzePipePlaceholder(right);
            if (!placeholder.has_placeholder) {
                try self.diags.add(
                    self.file.tokenLocation(pipe_token),
                    .syntax,
                    "pipe right-hand side must use at least one argument placeholder",
                    .{},
                );
            } else if (placeholder.invalid_token) |invalid| {
                try self.diags.add(
                    self.file.tokenLocation(invalid),
                    .syntax,
                    "pipe placeholders are only supported as '_', '&_', '$&_', '_.field', or '..variant' payload access for now",
                    .{},
                );
            }
            lhs = try self.addNode(.pipe_expression, pipe_token, .{ .node_and_node = .{ .first = lhs, .second = right } });
        }
        return lhs;
    }
'''
if text.count(old_pipe) != 1:
    raise RuntimeError(f"parsePipeExpr anchor changed: {text.count(old_pipe)}")
syntaxer.write_text(text.replace(old_pipe, new_pipe, 1))

pipeline = Path("src/0_commands/frontend_pipeline.zig")
text = pipeline.read_text()
old = '''    pub fn semantizeGlobalFiles(self: *FrontendPipeline, files: []const sf.SourceFile) !*const global_sg.GlobalSemanticGraph {
        _ = try self.parseFiles(files);
        try module_test_validate.validate(
'''
new = '''    pub fn semantizeGlobalFiles(self: *FrontendPipeline, files: []const sf.SourceFile) !*const global_sg.GlobalSemanticGraph {
        _ = try self.parseFiles(files);
        // Syntax diagnostics are terminal for this compilation. Continuing into
        // ModuleSema/GlobalSema can only manufacture secondary unresolved work
        // and pollute the primary parser diagnostic with internal debug noise.
        if (self.diagnostics.hasErrors()) return error.Reported;
        try module_test_validate.validate(
'''
if text.count(old) != 1:
    raise RuntimeError(f"frontend syntax barrier anchor changed: {text.count(old)}")
pipeline.write_text(text.replace(old, new, 1))

Path(".git/semantic-refactor-message").write_text("Validate pipe placeholder shapes in syntax\n")
