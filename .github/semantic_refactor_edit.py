from pathlib import Path

generic_functions = Path("src/4_semantics/global/generic_functions.zig")
text = generic_functions.read_text()

# Ambiguity is a deterministic semantic result, not a retryable/internal error.
old = '''                error.NoMatchingGenericFunction => return .not_applicable,
                error.DeferredGenericFunction => return .deferred,
                error.AmbiguousGenericFunction => return err,
                else => return .deferred,
'''
new = '''                error.NoMatchingGenericFunction => return .not_applicable,
                error.DeferredGenericFunction => return .deferred,
                error.AmbiguousGenericFunction => return .invalid,
                else => return .deferred,
'''
if text.count(old) != 1:
    raise RuntimeError(f"explicit generic ambiguity anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''                error.NoMatchingGenericFunction => return .not_applicable,
                error.DeferredGenericFunction => return .deferred,
                error.AmbiguousGenericFunction => return err,
                error.ConflictingGenericArgument => return err,
                else => return .deferred,
'''
new = '''                error.NoMatchingGenericFunction => return .not_applicable,
                error.DeferredGenericFunction => return .deferred,
                error.AmbiguousGenericFunction => return .invalid,
                error.ConflictingGenericArgument => return err,
                else => return .deferred,
'''
if text.count(old) != 1:
    raise RuntimeError(f"implicit generic ambiguity anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

# Let diagnostics ask the exact same generic selector which declarations tied.
old = '''        return self.resolveImplicitGenericFunctionFiltered(
            current_module,
            module.text(reference.name),
            module_filter,
            input,
        );
'''
new = '''        return self.resolveImplicitGenericFunctionFiltered(
            current_module,
            module.text(reference.name),
            module_filter,
            input,
            null,
        );
'''
if text.count(old) != 1:
    raise RuntimeError(f"source implicit generic wrapper anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''        return self.resolveImplicitGenericFunctionFiltered(current_module, name, null, input);
'''
new = '''        return self.resolveImplicitGenericFunctionFiltered(current_module, name, null, input, null);
'''
if text.count(old) != 1:
    raise RuntimeError(f"synthetic implicit generic wrapper anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''    fn resolveImplicitGenericFunctionFiltered(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input: global_sg.GlobalNodeId,
    ) !global_sg.GlobalFunctionId {
'''
new = '''    fn resolveImplicitGenericFunctionFiltered(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input: global_sg.GlobalNodeId,
        ambiguity_candidates: ?*std.ArrayList(global_sg.GlobalDeclId),
    ) !global_sg.GlobalFunctionId {
'''
if text.count(old) != 1:
    raise RuntimeError(f"implicit selector signature anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''                    .better => {
                        best = declaration;
                        best_arguments = range;
                        best_score = score;
                        best_specificity = specificity;
                        tied = false;
                    },
                    .worse => {},
                    .tie => if (declaration != best.?) {
                        tied = true;
                    },
'''
new = '''                    .better => {
                        best = declaration;
                        best_arguments = range;
                        best_score = score;
                        best_specificity = specificity;
                        tied = false;
                        if (ambiguity_candidates) |candidates| {
                            candidates.clearRetainingCapacity();
                            try candidates.append(self.allocator, declaration);
                        }
                    },
                    .worse => {},
                    .tie => if (declaration != best.?) {
                        tied = true;
                        if (ambiguity_candidates) |candidates|
                            try candidates.append(self.allocator, declaration);
                    },
'''
# There are explicit and implicit candidate loops with the same structure;
# only the latter is after resolveImplicitGenericFunctionFiltered.
selector_start = text.index('    fn resolveImplicitGenericFunctionFiltered(')
selector_end = text.index('    const ParameterizedSpecificity = struct', selector_start)
selector = text[selector_start:selector_end]
if selector.count(old) != 1:
    raise RuntimeError(f"implicit candidate ordering anchor changed: {selector.count(old)}")
text = text[:selector_start] + selector.replace(old, new, 1) + text[selector_end:]

anchor = '''    const ParameterizedSpecificity = struct {
'''
insert = '''    /// Re-run implicit generic selection transactionally for diagnostics and
    /// report the declaration identities tied at the best rank. This keeps
    /// diagnostics coupled to the real inference/specificity algorithm rather
    /// than maintaining an approximate second overload matcher.
    pub fn collectImplicitGenericAmbiguity(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        candidates: *std.ArrayList(global_sg.GlobalDeclId),
    ) !bool {
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        inline for (pools, 0..) |pool, index|
            lengths[index] = @field(self.graph, pool.name).items.len;
        const saved_stats = self.stats;
        const saved_generic_stats = self.generics.stats;
        const saved_core_stats = self.core.stats;
        defer {
            inline for (pools, 0..) |pool, index|
                @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            self.stats = saved_stats;
            self.generics.stats = saved_generic_stats;
            self.core.stats = saved_core_stats;
        }

        candidates.clearRetainingCapacity();
        const module_filter = if (reference.module_path) |path|
            try self.core.findModuleForQualifier(current_module, module.text(path))
        else
            null;
        _ = self.resolveImplicitGenericFunctionFiltered(
            current_module,
            module.text(reference.name),
            module_filter,
            input,
            candidates,
        ) catch |err| return switch (err) {
            error.AmbiguousGenericFunction => true,
            else => false,
        };
        return false;
    }

'''
if text.count(anchor) != 1:
    raise RuntimeError(f"specificity insertion anchor changed: {text.count(anchor)}")
text = text.replace(anchor, insert + anchor, 1)
generic_functions.write_text(text)

semantizer = Path("src/4_semantics/global/semantizer.zig")
text = semantizer.read_text()

old = '''            if (try diagnoseUnresolvedCall(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                return error.Reported;
'''
new = '''            if (try diagnoseUnresolvedCall(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, &generic_functions, diagnostics))
                return error.Reported;
'''
if text.count(old) != 1:
    raise RuntimeError(f"diagnose call invocation anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

start = text.index('fn diagnoseUnresolvedCall(')
body_start = text.index('    var flat: usize = 0;', start)
head = text[start:body_start]
old = '''    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
'''
new = '''    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    generic_functions: *generic_functions_mod.Resolver,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
'''
if head.count(old) != 1:
    raise RuntimeError(f"diagnose call parameter anchor changed: {head.count(old)}")
text = text[:start] + head.replace(old, new, 1) + text[body_start:]

# Insert generic ambiguity detection after the already-shared ordinary matcher.
old = '''            if (best_matches.items.len > 1) {
                var ambiguity = std.array_list.Managed(u8).init(allocator);
                defer ambiguity.deinit();
                try ambiguity.appendSlice("ambiguous call to '");
                try ambiguity.appendSlice(name);
                try ambiguity.appendSlice("' for arguments ");
                try appendValueShape(&ambiguity, graph, input);
                try ambiguity.appendSlice(". Possible overloads:");
                for (best_matches.items) |candidate| {
                    const function = graph.functions.items[@intFromEnum(candidate)];
                    try ambiguity.appendSlice("\\n  - ");
                    try ambiguity.appendSlice(name);
                    try ambiguity.append(' ');
                    try appendFieldShape(&ambiguity, graph, function.input);
                    try ambiguity.appendSlice(" -> ");
                    try appendFieldShape(&ambiguity, graph, function.output);
                }
                try diagnostics.add(
                    diagnosticLocation(graph, diagnostics, source),
                    .semantic,
                    "{s}",
                    .{ambiguity.items},
                );
                return true;
            }

            var message = std.array_list.Managed(u8).init(allocator);
'''
new = '''            if (best_matches.items.len > 1) {
                var ambiguity = std.array_list.Managed(u8).init(allocator);
                defer ambiguity.deinit();
                try ambiguity.appendSlice("ambiguous call to '");
                try ambiguity.appendSlice(name);
                try ambiguity.appendSlice("' for arguments ");
                try appendValueShape(&ambiguity, graph, input);
                try ambiguity.appendSlice(". Possible overloads:");
                for (best_matches.items) |candidate| {
                    const function = graph.functions.items[@intFromEnum(candidate)];
                    try ambiguity.appendSlice("\\n  - ");
                    try ambiguity.appendSlice(name);
                    try ambiguity.append(' ');
                    try appendFieldShape(&ambiguity, graph, function.input);
                    try ambiguity.appendSlice(" -> ");
                    try appendFieldShape(&ambiguity, graph, function.output);
                }
                try diagnostics.add(
                    diagnosticLocation(graph, diagnostics, source),
                    .semantic,
                    "{s}",
                    .{ambiguity.items},
                );
                return true;
            }

            var generic_ties: std.ArrayList(global_sg.GlobalDeclId) = .empty;
            defer generic_ties.deinit(allocator);
            if (try generic_functions.collectImplicitGenericAmbiguity(
                module_index,
                module,
                reference,
                input_id,
                &generic_ties,
            )) {
                var ambiguity = std.array_list.Managed(u8).init(allocator);
                defer ambiguity.deinit();
                try ambiguity.appendSlice("ambiguous call to '");
                try ambiguity.appendSlice(name);
                try ambiguity.appendSlice("' for arguments ");
                try appendValueShape(&ambiguity, graph, input);
                try ambiguity.appendSlice(". Possible overloads:");
                for (generic_ties.items) |declaration_id| {
                    const declaration = graph.declaration(declaration_id);
                    const function_id = declaration.function_id orelse continue;
                    const function = graph.functions.items[@intFromEnum(function_id)];
                    try ambiguity.appendSlice("\\n  - ");
                    try ambiguity.appendSlice(name);
                    try ambiguity.append(' ');
                    try appendFieldShape(&ambiguity, graph, function.input);
                    try ambiguity.appendSlice(" -> ");
                    try appendFieldShape(&ambiguity, graph, function.output);
                }
                try diagnostics.add(
                    diagnosticLocation(graph, diagnostics, source),
                    .semantic,
                    "{s}",
                    .{ambiguity.items},
                );
                return true;
            }

            var message = std.array_list.Managed(u8).init(allocator);
'''
if text.count(old) != 1:
    raise RuntimeError(f"ordinary ambiguity block anchor changed: {text.count(old)}")
semantizer.write_text(text.replace(old, new, 1))

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/polymorphism/02X_multiple_dispatch_ambiguous "
    "-Dtest-filter=feature_tests/polymorphism/24_abstract_dispatch_beats_regular_generic_with_defaults "
    "-Dtest-filter=feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous\n"
)
Path(".git/semantic-refactor-message").write_text("Diagnose ambiguous generic overloads\n")
