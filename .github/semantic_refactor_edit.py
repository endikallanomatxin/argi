from pathlib import Path

dispatch = Path("src/4_semantics/global/dispatch.zig")
text = dispatch.read_text()
old = '''const module_sg = @import("../module/graph.zig");
'''
new = '''const std = @import("std");
const module_sg = @import("../module/graph.zig");
'''
if text.count(old) != 1:
    raise RuntimeError(f"dispatch import anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''    ) !resolution.Result {
        const error_result = try self.errors.tryResolveCall(module_index, module, o, operation);
        if (!error_result.allowsFallback()) return error_result;
        const core_result = try self.core.tryResolve(module_index, module, o, operation);
        if (!core_result.allowsFallback()) return core_result;
'''
new = '''    ) !resolution.Result {
        const call = switch (operation) {
            .resolve_call => |value| value,
            else => unreachable,
        };
        const reference = module.semantic.external_refs.items[@intFromEnum(call.callee)];
        const trace = std.mem.eql(u8, module.text(reference.name), "DynamicArray");

        const error_result = try self.errors.tryResolveCall(module_index, module, o, operation);
        if (trace) std.debug.print("[dispatch-trace] errors={s}\\n", .{@tagName(error_result)});
        if (!error_result.allowsFallback()) return error_result;
        const core_result = try self.core.tryResolve(module_index, module, o, operation);
        if (trace) std.debug.print("[dispatch-trace] core={s}\\n", .{@tagName(core_result)});
        if (!core_result.allowsFallback()) return core_result;
'''
if text.count(old) != 1:
    raise RuntimeError(f"dispatch opening anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        if (!abstract_ordinary_result.allowsFallback()) return abstract_ordinary_result;

        const generic_result = try self.generic_functions.tryResolve(module_index, module, o, operation);
        if (!generic_result.allowsFallback()) return generic_result;

        const constructor_result = try self.constructors.tryResolve(module_index, module, o, operation);
        if (!constructor_result.allowsFallback()) return constructor_result;
'''
new = '''        if (trace) std.debug.print("[dispatch-trace] abstract_ordinary={s}\\n", .{@tagName(abstract_ordinary_result)});
        if (!abstract_ordinary_result.allowsFallback()) return abstract_ordinary_result;

        const generic_result = try self.generic_functions.tryResolve(module_index, module, o, operation);
        if (trace) std.debug.print("[dispatch-trace] generic={s}\\n", .{@tagName(generic_result)});
        if (!generic_result.allowsFallback()) return generic_result;

        const constructor_result = try self.constructors.tryResolve(module_index, module, o, operation);
        if (trace) std.debug.print("[dispatch-trace] constructor={s}\\n", .{@tagName(constructor_result)});
        if (!constructor_result.allowsFallback()) return constructor_result;
'''
if text.count(old) != 1:
    raise RuntimeError(f"dispatch middle anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
dispatch.write_text(text)

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/control_flow/14_for_mut_borrowed_dynamic_array\n"
)
Path(".git/semantic-refactor-message").write_text("Trace DynamicArray call ownership\n")
