from pathlib import Path

constructors = Path("src/4_semantics/global/constructors.zig")
text = constructors.read_text()

old = '''        _ = generics.ensureGenericInstance(ty) catch return .deferred;
'''
new = '''        _ = generics.ensureGenericInstance(ty) catch |err| {
            std.debug.print("[constructor-trace] ensureGenericInstance: {s}\\n", .{@errorName(err)});
            return .deferred;
        };
'''
if text.count(old) != 1:
    raise RuntimeError(f"explicit generic instance anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        if (tied or best_declaration == null) return result;
        result.function = generic_functions.instantiate(best_declaration.?, arguments) catch return result;
        return result;
'''
new = '''        if (tied or best_declaration == null) {
            std.debug.print("[constructor-trace] initializer selection tied={} best={} visible={}\\n", .{ tied, best_declaration != null, result.has_visible_initializer });
            return result;
        }
        result.function = generic_functions.instantiate(best_declaration.?, arguments) catch |err| {
            std.debug.print("[constructor-trace] instantiate init: {s}\\n", .{@errorName(err)});
            return result;
        };
        std.debug.print("[constructor-trace] explicit init instantiated\\n", .{});
        return result;
'''
if text.count(old) != 1:
    raise RuntimeError(f"generic initializer materialization anchor changed: {text.count(old)}")
constructors.write_text(text)

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/control_flow/14_for_mut_borrowed_dynamic_array\n"
)
Path(".git/semantic-refactor-message").write_text("Trace explicit generic constructor deferral\n")
