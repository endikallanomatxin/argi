from pathlib import Path

generic_functions = Path("src/4_semantics/global/generic_functions.zig")
text = generic_functions.read_text()
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
generic_functions.write_text(text.replace(old, new, 1))

semantizer = Path("src/4_semantics/global/semantizer.zig")
text = semantizer.read_text()
old = '''const abstract_mod = @import("abstracts.zig");
const error_mod = @import("errors.zig");
'''
new = '''const abstract_mod = @import("abstracts.zig");
const call_compatibility = @import("call_compatibility.zig");
const error_mod = @import("errors.zig");
'''
if text.count(old) != 1:
    raise RuntimeError(f"call compatibility import anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''            if (try diagnoseUnresolvedCall(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                return error.Reported;
'''
new = '''            if (try diagnoseUnresolvedCall(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, &abstracts, diagnostics))
                return error.Reported;
'''
if text.count(old) != 1:
    raise RuntimeError(f"diagnose call invocation anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
'''
new = '''    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    abstracts: *abstract_mod.Resolver,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
'''
# This parameter tail occurs in several diagnostic helpers. Restrict the
# replacement to diagnoseUnresolvedCall's function slice.
start = text.index('fn diagnoseUnresolvedCall(')
end = text.index('    var flat: usize = 0;', start)
head = text[start:end]
if head.count(old) != 1:
    raise RuntimeError(f"diagnose call parameter anchor changed: {head.count(old)}")
text = text[:start] + head.replace(old, new, 1) + text[end:]

old = '''            for (candidates.items) |candidate| {
                const function = graph.functions.items[@intFromEnum(candidate)];
                if (function.flags.is_abstract_dispatch) continue;
                const score = switch (diagnostic_core.matchCallInput(function.input, input_id)) {
                    .score => |value| value,
                    .no_match, .deferred => continue,
                };
'''
new = '''            for (candidates.items) |candidate| {
                const function = graph.functions.items[@intFromEnum(candidate)];
                // Parameterized abstract calls retain their declaration-time
                // source signature in GlobalSG. Use abstract compatibility for
                // those placeholders so diagnostics show the declared pattern
                // (`A`) rather than an inferred substitution (`Int32`).
                const score_match = if (function.flags.is_abstract_dispatch)
                    call_compatibility.matchInput(.{ .core = &diagnostic_core, .abstracts = abstracts }, function.input, input_id)
                else
                    diagnostic_core.matchCallInput(function.input, input_id);
                const score = switch (score_match) {
                    .score => |value| value,
                    .no_match, .deferred => continue,
                };
'''
if text.count(old) != 1:
    raise RuntimeError(f"ambiguity diagnostic scoring anchor changed: {text.count(old)}")
semantizer.write_text(text.replace(old, new, 1))

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/polymorphism/02X_multiple_dispatch_ambiguous "
    "-Dtest-filter=feature_tests/polymorphism/24_abstract_dispatch_beats_regular_generic_with_defaults "
    "-Dtest-filter=feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous\n"
)
Path(".git/semantic-refactor-message").write_text("Diagnose ambiguous generic overloads\n")
