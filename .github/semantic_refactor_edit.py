from pathlib import Path

path = Path("src/4_semantics/global/generic_functions.zig")
text = path.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"expected exactly one match, found {count}: {old[:120]!r}")
    text = text.replace(old, new, 1)


# Track declaration specificity independently from compatibility after
# substitution. Otherwise a free T inferred as Int32 becomes indistinguishable
# from a declaration that actually constrained the call to Int32.
replace_once(
    "        var best_score: u32 = 0;\n        var tied = false;\n        var saw_deferred = false;\n",
    "        var best_score: u32 = 0;\n        var best_specificity: ParameterizedSpecificity = .{};\n        var tied = false;\n        var saw_deferred = false;\n",
)

replace_once(
    "                if (best == null or score > best_score) {\n"
    "                    best = declaration;\n"
    "                    best_arguments = complete_arguments;\n"
    "                    best_score = score;\n"
    "                    tied = false;\n"
    "                } else if (score == best_score and declaration != best.?) tied = true;\n",
    "                const specificity = self.parameterizedInputSpecificity(candidate_index, parameterized.input, input);\n"
    "                const ordering: CandidateOrdering = if (best == null) .better else compareCandidates(specificity, score, best_specificity, best_score);\n"
    "                switch (ordering) {\n"
    "                    .better => {\n"
    "                        best = declaration;\n"
    "                        best_arguments = complete_arguments;\n"
    "                        best_score = score;\n"
    "                        best_specificity = specificity;\n"
    "                        tied = false;\n"
    "                    },\n"
    "                    .worse => {},\n"
    "                    .tie => if (declaration != best.?) {\n"
    "                        tied = true;\n"
    "                    },\n"
    "                }\n",
)

replace_once(
    "        var best_score: u32 = 0;\n        var best_kind: parameterized_storage.GenericDispatchKind = .abstract_contract;\n        var tied = false;\n",
    "        var best_score: u32 = 0;\n        var best_specificity: ParameterizedSpecificity = .{};\n        var tied = false;\n",
)

replace_once(
    "                const regular_wins_tie = parameterized.dispatch_kind == .regular and best_kind == .abstract_contract;\n"
    "                if (best == null or score > best_score or (score == best_score and regular_wins_tie)) {\n"
    "                    best = declaration;\n"
    "                    best_arguments = range;\n"
    "                    best_score = score;\n"
    "                    best_kind = parameterized.dispatch_kind;\n"
    "                    tied = false;\n"
    "                } else if (score == best_score and parameterized.dispatch_kind == best_kind and declaration != best.?) tied = true;\n",
    "                const specificity = self.parameterizedInputSpecificity(candidate_index, parameterized.input, input);\n"
    "                const ordering: CandidateOrdering = if (best == null) .better else compareCandidates(specificity, score, best_specificity, best_score);\n"
    "                switch (ordering) {\n"
    "                    .better => {\n"
    "                        best = declaration;\n"
    "                        best_arguments = range;\n"
    "                        best_score = score;\n"
    "                        best_specificity = specificity;\n"
    "                        tied = false;\n"
    "                    },\n"
    "                    .worse => {},\n"
    "                    .tie => if (declaration != best.?) {\n"
    "                        tied = true;\n"
    "                    },\n"
    "                }\n",
)

marker = "    fn matchParameterizedInput(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId, bindings: *generic_mod.Resolver.Bindings, input: global_sg.GlobalNodeId) core_mod.Resolver.CallInputMatch {\n"
if text.count(marker) != 1:
    raise RuntimeError("matchParameterizedInput marker changed")

helpers = r'''    const ParameterizedSpecificity = struct {
        /// Exact nominal/builtin leaves. Exactness also satisfies the weaker
        /// "bounded" dimension so a concrete type dominates an abstract bound.
        exact: u32 = 0,
        bounded: u32 = 0,
        /// Fixed type constructors such as pointer/array/structural shape.
        structure: u32 = 0,

        fn add(self: *ParameterizedSpecificity, other: ParameterizedSpecificity) void {
            self.exact += other.exact;
            self.bounded += other.bounded;
            self.structure += other.structure;
        }
    };

    const SpecificityOrdering = enum { less, equal, greater, incomparable };
    const CandidateOrdering = enum { better, worse, tie };

    fn compareSpecificity(left: ParameterizedSpecificity, right: ParameterizedSpecificity) SpecificityOrdering {
        if (left.exact == right.exact and left.bounded == right.bounded and left.structure == right.structure) return .equal;
        const left_at_least = left.exact >= right.exact and left.bounded >= right.bounded and left.structure >= right.structure;
        const right_at_least = right.exact >= left.exact and right.bounded >= left.bounded and right.structure >= left.structure;
        if (left_at_least) return .greater;
        if (right_at_least) return .less;
        return .incomparable;
    }

    fn compareCandidates(
        candidate_specificity: ParameterizedSpecificity,
        candidate_score: u32,
        best_specificity: ParameterizedSpecificity,
        best_score: u32,
    ) CandidateOrdering {
        return switch (compareSpecificity(candidate_specificity, best_specificity)) {
            .greater => .better,
            .less => .worse,
            // Compatibility remains a useful discriminator when declarations
            // impose the same restrictions, or restrictions on orthogonal
            // dimensions. Equal quality in the latter case is ambiguous.
            .equal, .incomparable => if (candidate_score > best_score)
                .better
            else if (candidate_score < best_score)
                .worse
            else
                .tie,
        };
    }

    fn exactSpecificity() ParameterizedSpecificity {
        return .{ .exact = 1, .bounded = 1 };
    }

    fn parameterizedInputSpecificity(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
    ) ParameterizedSpecificity {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return self.parameterizedTypeSpecificity(module_index, pattern),
        };
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |resolved| switch (resolved) {
                .structural => |value| value,
                else => return self.parameterizedTypeSpecificity(module_index, pattern),
            },
            else => return self.parameterizedTypeSpecificity(module_index, pattern),
        };

        var specificity: ParameterizedSpecificity = .{};
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |supplied, supplied_position| {
            const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(supplied.name).len == 0;
            var matched: ?ir.ParameterizedTypeId = null;
            if (positional) {
                if (supplied_position < shape.fields.len) {
                    matched = storage.fields.items[shape.fields.start + @as(u32, @intCast(supplied_position))].ty;
                }
            } else {
                for (storage.fields.items[shape.fields.start..][0..shape.fields.len]) |field| {
                    if (!std.mem.eql(u8, self.modules[module_index].text(field.name), self.graph.text(supplied.name))) continue;
                    matched = field.ty;
                    break;
                }
            }
            if (matched) |field_type| specificity.add(self.parameterizedTypeSpecificity(module_index, field_type));
        }
        return specificity;
    }

    fn parameterizedTypeSpecificity(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
    ) ParameterizedSpecificity {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        return switch (storage.types.items[@intFromEnum(pattern)]) {
            .parameter => |parameter| if (module.semantic.parameterized_storage.comptime_parameters.items[@intFromEnum(parameter)].constraint != null)
                .{ .bounded = 1 }
            else
                .{},
            .abstract_self => .{ .bounded = 1 },
            .concrete, .external => exactSpecificity(),
            .array => |array| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                result.add(self.parameterizedIntSpecificity(module_index, array.length));
                result.add(self.parameterizedTypeSpecificity(module_index, array.element));
                break :blk result;
            },
            .resolved => |resolved| self.resolvedPatternSpecificity(module_index, resolved),
        };
    }

    fn parameterizedIntSpecificity(
        self: *Resolver,
        module_index: usize,
        expression: ir.ParameterizedIntExprId,
    ) ParameterizedSpecificity {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        return switch (storage.int_expressions.items[@intFromEnum(expression)]) {
            .literal => exactSpecificity(),
            .parameter => .{},
            .binary => |binary| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                result.add(self.parameterizedIntSpecificity(module_index, binary.left));
                result.add(self.parameterizedIntSpecificity(module_index, binary.right));
                break :blk result;
            },
        };
    }

    fn resolvedPatternSpecificity(
        self: *Resolver,
        module_index: usize,
        resolved: ir.ResolvedType,
    ) ParameterizedSpecificity {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        return switch (resolved) {
            .builtin => |builtin| if (builtin == .Any) .{} else exactSpecificity(),
            .declared => exactSpecificity(),
            .pointer => |pointer| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                result.add(self.parameterizedTypeSpecificity(module_index, pointer.child));
                break :blk result;
            },
            .array => |array| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                result.add(exactSpecificity());
                result.add(self.parameterizedTypeSpecificity(module_index, array.element));
                break :blk result;
            },
            .nullable, .inferred_errable, .virtual => |child| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                result.add(self.parameterizedTypeSpecificity(module_index, child));
                break :blk result;
            },
            .generic => |generic| blk: {
                var result = exactSpecificity();
                result.structure += 1;
                for (storage.generic_arguments.items[generic.arguments.start..][0..generic.arguments.len]) |argument| switch (argument.value) {
                    .type => |ty| result.add(self.parameterizedTypeSpecificity(module_index, ty)),
                    .comptime_int => |value| result.add(self.parameterizedIntSpecificity(module_index, value)),
                };
                break :blk result;
            },
            .structural => |shape| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                for (storage.fields.items[shape.fields.start..][0..shape.fields.len]) |field| {
                    result.structure += 1;
                    result.add(self.parameterizedTypeSpecificity(module_index, field.ty));
                }
                break :blk result;
            },
            .structural_choice => |shape| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                for (storage.variants.items[shape.variants.start..][0..shape.variants.len]) |variant| {
                    result.structure += 1;
                    if (variant == .semantic) if (variant.semantic.payload_type) |payload|
                        result.add(self.parameterizedTypeSpecificity(module_index, payload));
                }
                break :blk result;
            },
            .inferred_choice => .{ .structure = 1 },
        };
    }

'''
text = text.replace(marker, helpers + marker, 1)

path.write_text(text)
Path(".git/semantic-refactor-message").write_text("Rank generic overloads by declared specificity\n")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/polymorphism/24_abstract_dispatch_beats_regular_generic_with_defaults "
    "-Dtest-filter=feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous "
    "-Dtest-filter=feature_tests/modules/24_imported_generic_abstract_dispatch_prefers_concrete\n"
)
