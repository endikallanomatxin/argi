from pathlib import Path

core = Path("src/4_semantics/global/core.zig")
text = core.read_text()

old = '''    pub const FunctionMatch = union(enum) {
        no_match,
        deferred,
        function: global_sg.GlobalFunctionId,
    };
'''
new = '''    pub const FunctionMatch = union(enum) {
        no_match,
        deferred,
        ambiguous,
        function: global_sg.GlobalFunctionId,
    };
'''
if text.count(old) != 1:
    raise RuntimeError(f"FunctionMatch anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        if (best) |function| {
            if (tied) return error.AmbiguousGlobalFunction;
            return .{ .function = function };
        }
'''
new = '''        if (best) |function| {
            if (tied) return .ambiguous;
            return .{ .function = function };
        }
'''
if text.count(old) != 1:
    raise RuntimeError(f"ordinary ambiguity anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        return switch (try self.matchFunctionByName(current_module, reference, input_node)) {
            .function => |function| function,
            .no_match => error.NoMatchingGlobalFunction,
            .deferred => error.DeferredGlobalFunction,
        };
'''
new = '''        return switch (try self.matchFunctionByName(current_module, reference, input_node)) {
            .function => |function| function,
            .no_match => error.NoMatchingGlobalFunction,
            .deferred => error.DeferredGlobalFunction,
            .ambiguous => error.AmbiguousGlobalFunction,
        };
'''
if text.count(old) != 1:
    raise RuntimeError(f"resolveFunctionByName anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        const function = switch (try self.matchFunctionByName(module_index, reference, input)) {
            .no_match => return .not_applicable,
            .deferred => return .deferred,
            .function => |function| function,
        };
'''
new = '''        const function = switch (try self.matchFunctionByName(module_index, reference, input)) {
            .no_match => return .not_applicable,
            .deferred => return .deferred,
            .ambiguous => return .invalid,
            .function => |function| function,
        };
'''
if text.count(old) != 1:
    raise RuntimeError(f"resolveCall match anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        if (expected_pointer.mutability == .read_write and actual_pointer.mutability != .read_write) return false;
        if (types.equal(self.graph, actual_pointer.child, expected_pointer.child)) return true;
        return switch (self.graph.types.items[@intFromEnum(actual_pointer.child)]) {
            .virtual => |abstract_type| types.equal(self.graph, abstract_type, expected_pointer.child),
            else => false,
        };
'''
new = '''        if (expected_pointer.mutability == .read_write and actual_pointer.mutability != .read_write) return false;
        if (types.equal(self.graph, actual_pointer.child, expected_pointer.child)) return true;
        // `Any` is the wildcard value type. A reference to a concrete value is
        // compatible with `&Any`/`$&Any`, subject to the mutability rule above.
        // Do not recurse through pointer constructors here: that would make
        // mutable pointer slots covariant (`&&Int32` -> `&&Any`).
        if (types.isBuiltin(self.graph, expected_pointer.child, .Any)) return true;
        return switch (self.graph.types.items[@intFromEnum(actual_pointer.child)]) {
            .virtual => |abstract_type| types.equal(self.graph, abstract_type, expected_pointer.child),
            else => false,
        };
'''
if text.count(old) != 1:
    raise RuntimeError(f"reference compatibility anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
core.write_text(text)

compat = Path("src/4_semantics/global/call_compatibility.zig")
text = compat.read_text()
old = '''    const function = switch (try matchFunctionByName(compatibility, module_index, module, reference, input)) {
        .no_match => return .not_applicable,
        .deferred => return .deferred,
        .function => |function| function,
    };
'''
new = '''    const function = switch (try matchFunctionByName(compatibility, module_index, module, reference, input)) {
        .no_match => return .not_applicable,
        .deferred => return .deferred,
        .ambiguous => return .invalid,
        .function => |function| function,
    };
'''
if text.count(old) != 1:
    raise RuntimeError(f"abstract ordinary dispatch anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''    if (best) |function| {
        if (tied) return error.AmbiguousGlobalFunction;
        return .{ .function = function };
    }
'''
new = '''    if (best) |function| {
        if (tied) return .ambiguous;
        return .{ .function = function };
    }
'''
if text.count(old) != 1:
    raise RuntimeError(f"abstract ordinary ambiguity anchor changed: {text.count(old)}")
compat.write_text(text.replace(old, new, 1))

control = Path("src/4_semantics/global/control.zig")
text = control.read_text()
old = '''    const SyntheticCallResult = union(enum) {
        no_match,
        deferred,
        call: global_sg.GlobalNodeId,
    };
'''
new = '''    const SyntheticCallResult = union(enum) {
        no_match,
        deferred,
        invalid,
        call: global_sg.GlobalNodeId,
    };
'''
if text.count(old) != 1:
    raise RuntimeError(f"synthetic result anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        const function = switch (try core.matchUnqualifiedFunctionByName(module_index, name, input)) {
            .function => |function| function,
            .deferred => return .deferred,
            .no_match => generic_functions.resolveImplicitGenericFunctionByName(module_index, name, input) catch |err| switch (err) {
                error.NoMatchingGenericFunction => return .no_match,
                error.DeferredGenericFunction => return .deferred,
                error.ConflictingGenericArgument => return .no_match,
                else => return err,
            },
        };
'''
new = '''        const function = switch (try core.matchUnqualifiedFunctionByName(module_index, name, input)) {
            .function => |function| function,
            .deferred => return .deferred,
            .ambiguous => return .invalid,
            .no_match => generic_functions.resolveImplicitGenericFunctionByName(module_index, name, input) catch |err| switch (err) {
                error.NoMatchingGenericFunction => return .no_match,
                error.DeferredGenericFunction => return .deferred,
                error.AmbiguousGenericFunction => return .invalid,
                error.ConflictingGenericArgument => return .no_match,
                else => return err,
            },
        };
'''
if text.count(old) != 1:
    raise RuntimeError(f"synthetic dispatch anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

# Every synthetic protocol call maps deterministic ambiguity back to the
# enclosing for-each operation's common invalid state.
old = '''            .call => |node| node,
            .deferred => return .deferred,
            .no_match => return .invalid,
'''
new = '''            .call => |node| node,
            .deferred => return .deferred,
            .no_match, .invalid => return .invalid,
'''
count = text.count(old)
if count != 3:
    raise RuntimeError(f"for synthetic result anchors changed: {count}")
text = text.replace(old, new)
control.write_text(text)

semantizer = Path("src/4_semantics/global/semantizer.zig")
text = semantizer.read_text()
old = '''fn diagnoseUnresolvedCall(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
'''
new = '''fn diagnoseUnresolvedCall(
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
'''
if text.count(old) != 1:
    raise RuntimeError(f"diagnose call signature anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''            if (candidates.items.len == 0) continue;

            var message = std.array_list.Managed(u8).init(allocator);
'''
new = '''            if (candidates.items.len == 0) continue;

            // Reuse Core's matcher to distinguish a deterministic ambiguity
            // from a genuine no-match. Resolution and diagnostics must agree
            // on compatibility and scoring rather than maintaining parallel
            // overload rules.
            var diagnostic_core = core_mod.Resolver{
                .allocator = allocator,
                .graph = graph,
                .modules = modules,
                .offsets = offsets,
            };
            var best_matches: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
            defer best_matches.deinit(allocator);
            var best_score: ?u32 = null;
            for (candidates.items) |candidate| {
                const function = graph.functions.items[@intFromEnum(candidate)];
                if (function.flags.is_abstract_dispatch) continue;
                const score = switch (diagnostic_core.matchCallInput(function.input, input_id)) {
                    .score => |value| value,
                    .no_match, .deferred => continue,
                };
                if (best_score == null or score > best_score.?) {
                    best_score = score;
                    best_matches.clearRetainingCapacity();
                    try best_matches.append(allocator, candidate);
                } else if (score == best_score.?) {
                    try best_matches.append(allocator, candidate);
                }
            }
            if (best_matches.items.len > 1) {
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
if text.count(old) != 1:
    raise RuntimeError(f"diagnostic candidate anchor changed: {text.count(old)}")
semantizer.write_text(text.replace(old, new, 1))

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/polymorphism/01_multiple_dispatch "
    "-Dtest-filter=feature_tests/polymorphism/02X_multiple_dispatch_ambiguous\n"
)
Path(".git/semantic-refactor-message").write_text("Diagnose ambiguous ordinary overloads\n")
