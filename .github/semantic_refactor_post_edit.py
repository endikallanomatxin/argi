from pathlib import Path
import subprocess

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    return text.replace(old, new, 1)

core_path = Path("src/4_semantics/global/core.zig")
core = core_path.read_text()

ordinary_anchor = '''    fn matchFunctionNamed(
'''
reach_matcher = '''    pub fn matchUnqualifiedFunctionByNameWithReach(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !FunctionMatch {
        var best: ?global_sg.GlobalFunctionId = null;
        var best_score: u32 = 0;
        var tied = false;
        var saw_deferred = false;
        for (self.graph.functions.items, 0..) |function, raw| {
            if (function.flags.is_abstract_dispatch) continue;
            const decl = self.graph.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, self.graph.text(decl.name), name)) continue;
            if (!self.declarationVisible(current_module, function.declaration, null)) continue;
            const score = switch (try self.matchCallInputWithReach(function.input, input_node, context)) {
                .no_match => continue,
                .deferred => {
                    saw_deferred = true;
                    continue;
                },
                .score => |score| score,
            };
            if (best == null or score > best_score) {
                best = @enumFromInt(@as(u32, @intCast(raw)));
                best_score = score;
                tied = false;
            } else if (score == best_score) tied = true;
        }
        if (best) |function| {
            if (tied) return .ambiguous;
            return .{ .function = function };
        }
        if (saw_deferred) return .deferred;
        return .no_match;
    }

'''
if ordinary_anchor not in core:
    raise RuntimeError("reach-aware ordinary matcher insertion anchor missing")
core = core.replace(ordinary_anchor, reach_matcher + ordinary_anchor, 1)

input_anchor = '''    pub fn callInputNamesMatch(self: *const Resolver, expected_fields: global_sg.FieldRange, literal: anytype) bool {
'''
input_helpers = '''    pub fn matchCallInputWithReach(
        self: *Resolver,
        expected_fields: global_sg.FieldRange,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !CallInputMatch {
        const base = self.matchCallInput(expected_fields, input_node);
        if (base != .score) return base;
        const literal = switch (self.graph.nodes.items[@intFromEnum(input_node)].content) {
            .struct_value_literal => |value| value,
            else => return .no_match,
        };
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            if (self.callArgument(literal, offset, expected.name) != null) continue;
            const fallback = expected.default_value orelse return .no_match;
            if (self.graph.nodes.items[@intFromEnum(fallback)].content != .reach_directive) continue;
            switch (try self.probeReachedDefault(context, expected, fallback)) {
                .available => {},
                .deferred => return .deferred,
                .unavailable => return .no_match,
            }
        }
        return base;
    }

    const ReachedDefaultProbe = enum { unavailable, deferred, available };

    fn probeReachedDefault(
        self: *Resolver,
        context: reach_context.Context,
        expected_field: global_sg.Field,
        default_node: global_sg.GlobalNodeId,
    ) !ReachedDefaultProbe {
        const reach_id = self.graph.nodes.items[@intFromEnum(default_node)].content.reach_directive;
        const reach = self.graph.reaches.items[@intFromEnum(reach_id)];
        var saw_deferred = false;

        for (self.graph.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len]) |alternative| {
            if (alternative.segments.len == 0) continue;
            const segments = self.graph.reach_segments.items[alternative.segments.start..][0..alternative.segments.len];
            const root_name = self.graph.text(segments[0]);
            var scope_index = context.bindingCount();
            while (scope_index > 0) {
                scope_index -= 1;
                const binding_id = context.bindingAt(scope_index);
                const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                if (!std.mem.eql(u8, self.graph.text(binding.name), root_name)) continue;
                if (self.graph.isBindingTypeUnresolved(binding_id) or self.graph.isTypeUnresolved(binding.ty)) {
                    saw_deferred = true;
                    continue;
                }

                var current_ty = binding.ty;
                var valid = true;
                for (segments[1..]) |segment| {
                    if (self.graph.isTypeUnresolved(current_ty)) {
                        saw_deferred = true;
                        valid = false;
                        break;
                    }
                    const hit = types.findField(self.graph, current_ty, self.graph.text(segment)) orelse {
                        valid = false;
                        break;
                    };
                    current_ty = hit.field.storage_type orelse hit.field.ty;
                }
                if (!valid) continue;
                if (self.graph.isTypeUnresolved(current_ty)) {
                    saw_deferred = true;
                    continue;
                }
                if (types.equal(self.graph, current_ty, expected_field.ty) or
                    self.callTypesCompatible(current_ty, expected_field.ty))
                    return .available;
            }
        }

        const owner_id = context.ownerFunction() orelse
            return if (saw_deferred) .deferred else .unavailable;
        const owner = self.graph.functions.items[@intFromEnum(owner_id)];
        const owner_name = self.graph.text(self.graph.declarations.items[@intFromEnum(owner.declaration)].name);
        if (std.mem.eql(u8, owner_name, "main"))
            return if (saw_deferred) .deferred else .unavailable;

        for (self.graph.fields.items[owner.input.start..][0..owner.input.len]) |field| {
            if (!std.mem.eql(u8, self.graph.text(field.name), self.graph.text(expected_field.name))) continue;
            if (self.graph.isTypeUnresolved(field.ty) or self.graph.isTypeUnresolved(expected_field.ty))
                return .deferred;
            return if (types.equal(self.graph, field.ty, expected_field.ty) or
                self.callTypesCompatible(field.ty, expected_field.ty) or
                self.callTypesCompatible(expected_field.ty, field.ty))
                .available
            else
                .unavailable;
        }

        // completeCallInputFieldsWithReach can propagate a missing reach
        // parameter into a non-main caller. Ranking may acknowledge that
        // possibility, but must not mutate the caller while probing overloads.
        return .available;
    }

'''
core = replace_once(core, input_anchor, input_helpers + input_anchor, "reach-aware input matcher")
core_path.write_text(core)

dispatch_path = Path("src/4_semantics/global/dispatch.zig")
dispatch = dispatch_path.read_text()
dispatch = replace_once(
    dispatch,
    "        const ordinary = try self.core.matchUnqualifiedFunctionByName(module_index, name, input);\n",
    "        const ordinary = try self.core.matchUnqualifiedFunctionByNameWithReach(module_index, name, input, reach);\n",
    "implicit ordinary reach ranking",
)
dispatch_path.write_text(dispatch)

generic_path = Path("src/4_semantics/global/generic_functions.zig")
generic = generic_path.read_text()
generic = replace_once(
    generic,
    '''            if (!try self.resolver.core.completeCallInputFields(self.resolver.graph.functions.items[@intFromEnum(function)].input, input)) return error.IncompleteParameterizedCallInput;
            return .{
''',
    '''            if (std.mem.eql(u8, name, "copy")) {
                const selected = self.resolver.graph.functions.items[@intFromEnum(function)];
                std.debug.print(
                    "[parameterized-copy] module={} fn={} decl={} generic={}\\n",
                    .{ self.module_index, @intFromEnum(function), @intFromEnum(selected.declaration), selected.flags.is_generic_instantiation },
                );
            }
            if (!try self.resolver.core.completeCallInputFields(self.resolver.graph.functions.items[@intFromEnum(function)].input, input)) return error.IncompleteParameterizedCallInput;
            return .{
''',
    "parameterized copy callee trace",
)
generic_path.write_text(generic)

for path in (core_path, dispatch_path, generic_path):
    subprocess.run(["zig", "fmt", str(path)], check=True)
