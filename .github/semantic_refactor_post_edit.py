from pathlib import Path
import subprocess

# Constructors need the generic unifier as an internal cross-resolver helper.
path = Path("src/4_semantics/global/generic_functions.zig")
text = path.read_text()
old = "    fn inferInputType(\n"
new = "    pub fn inferInputType(\n"
if text.count(old) != 1:
    raise RuntimeError(f"inferInputType visibility anchor changed: {text.count(old)}")
path.write_text(text.replace(old, new, 1))

# Temporary focused diagnostics. The edit workflow only commits src/ when the
# focused semantic test succeeds, so these prints never land in the branch.
path = Path("src/4_semantics/global/constructors.zig")
text = path.read_text()
old = '''                const arguments = generic_functions.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch return null;
                return generic_functions.instantiate(declaration, arguments) catch return null;
'''
new = '''                const arguments = generic_functions.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch |err| {
                    std.debug.print("[generic-init-materialize] declaration={} append-args={s}\\n", .{ @intFromEnum(declaration), @errorName(err) });
                    return null;
                };
                return generic_functions.instantiate(declaration, arguments) catch |err| {
                    std.debug.print("[generic-init-materialize] declaration={} instantiate={s}\\n", .{ @intFromEnum(declaration), @errorName(err) });
                    return null;
                };
'''
if text.count(old) != 1:
    raise RuntimeError(f"generic materialization trace anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        if (!try generic_functions.inferInputType(
            candidate_index,
            storage.fields.items[shape.fields.start].ty,
            destination_pointer,
            bindings,
        )) return false;
        if (!try self.inferInitializerUserBindings(generic_functions, candidate_index, parameterized.input, input, bindings)) return false;
        return self.inferInitializerReachBindings(generic_functions, candidate_index, parameterized.input, context, bindings);
'''
new = '''        if (!try generic_functions.inferInputType(
            candidate_index,
            storage.fields.items[shape.fields.start].ty,
            destination_pointer,
            bindings,
        )) {
            std.debug.print("[generic-init-bind] module={} destination=false\\n", .{candidate_index});
            return false;
        }
        if (!try self.inferInitializerUserBindings(generic_functions, candidate_index, parameterized.input, input, bindings)) {
            std.debug.print("[generic-init-bind] module={} user=false\\n", .{candidate_index});
            return false;
        }
        const reached = try self.inferInitializerReachBindings(generic_functions, candidate_index, parameterized.input, context, bindings);
        if (!reached) std.debug.print("[generic-init-bind] module={} reach=false\\n", .{candidate_index});
        return reached;
'''
if text.count(old) != 1:
    raise RuntimeError(f"generic binding trace anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''                if (valid) return current_ty;
'''
new = '''                if (valid) {
                    std.debug.print("[generic-init-reach] candidate-module={} root={s} type={}\\n", .{ candidate_index, root_name, @intFromEnum(current_ty) });
                    return current_ty;
                }
'''
if text.count(old) != 1:
    raise RuntimeError(f"generic reach trace anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

path.write_text(text)

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/core.zig",
    "src/4_semantics/global/constructors.zig",
    "src/4_semantics/global/generic_functions.zig",
], check=True)
