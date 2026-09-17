from pathlib import Path
import subprocess

path = Path("src/4_semantics/global/constructors.zig")
text = path.read_text()

old = '''    fn findGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        module_index: usize,
        constructed_ty: global_sg.GlobalTypeId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        input: global_sg.GlobalNodeId,
    ) !InitializerLookup {
        var result: InitializerLookup = .{};
'''
new = '''    fn findGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        module_index: usize,
        constructed_ty: global_sg.GlobalTypeId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        input: global_sg.GlobalNodeId,
    ) !InitializerLookup {
        const trace_generic_initializer = switch (self.graph.types.items[@intFromEnum(constructed_ty)]) {
            .generic => |identity| std.mem.eql(
                u8,
                self.graph.text(self.graph.declarations.items[@intFromEnum(identity.base)].name),
                "DynamicArray",
            ),
            else => false,
        };
        var result: InitializerLookup = .{};
'''
if text.count(old) != 1:
    raise RuntimeError(f"findGenericInitializer header anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''                const probe = try self.probeGenericInitializer(
                    generics,
                    candidate_module,
                    candidate_index,
                    parameterized,
                    constructed_ty,
                    arguments,
                    input,
                );
                if (!probe.owns_type) continue;
'''
new = '''                const probe = try self.probeGenericInitializer(
                    generics,
                    candidate_module,
                    candidate_index,
                    parameterized,
                    constructed_ty,
                    arguments,
                    input,
                    trace_generic_initializer,
                );
                if (trace_generic_initializer) std.debug.print(
                    "[generic-init-probe] module={} declaration={} owns={} scored={} score={}\\n",
                    .{ candidate_index, @intFromEnum(declaration_id), probe.owns_type, probe.score != null, probe.score orelse 0 },
                );
                if (!probe.owns_type) continue;
'''
if text.count(old) != 1:
    raise RuntimeError(f"generic initializer probe call anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''    fn probeGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        candidate_module: *const module_sg.ModuleSemanticGraph,
        candidate_index: usize,
        parameterized: anytype,
        constructed_ty: global_sg.GlobalTypeId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        input: global_sg.GlobalNodeId,
    ) !InitializerProbe {
'''
new = '''    fn probeGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        candidate_module: *const module_sg.ModuleSemanticGraph,
        candidate_index: usize,
        parameterized: anytype,
        constructed_ty: global_sg.GlobalTypeId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        input: global_sg.GlobalNodeId,
        trace: bool,
    ) !InitializerProbe {
'''
if text.count(old) != 1:
    raise RuntimeError(f"probeGenericInitializer signature anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        generics.bindGlobalArguments(candidate_index, parameterized.parameters, arguments, &bindings) catch return .{};
        const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch return .{};
        const fields = types.fields(self.graph, input_ty) orelse return .{};
        if (fields.len == 0) return .{};

        const destination = self.graph.fields.items[fields.start];
        const pointer = switch (self.graph.types.items[@intFromEnum(destination.ty)]) {
            .pointer => |pointer_value| pointer_value,
            else => return .{},
        };
        if (!types.equal(self.graph, pointer.child, constructed_ty)) return .{};
'''
new = '''        generics.bindGlobalArguments(candidate_index, parameterized.parameters, arguments, &bindings) catch |err| {
            if (trace) std.debug.print("[generic-init-probe-stage] module={} bind={s}\\n", .{ candidate_index, @errorName(err) });
            return .{};
        };
        const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch |err| {
            if (trace) std.debug.print("[generic-init-probe-stage] module={} instantiate-input={s}\\n", .{ candidate_index, @errorName(err) });
            return .{};
        };
        const fields = types.fields(self.graph, input_ty) orelse {
            if (trace) std.debug.print("[generic-init-probe-stage] module={} no-fields input-type={}\\n", .{ candidate_index, @intFromEnum(input_ty) });
            return .{};
        };
        if (fields.len == 0) {
            if (trace) std.debug.print("[generic-init-probe-stage] module={} empty-fields input-type={}\\n", .{ candidate_index, @intFromEnum(input_ty) });
            return .{};
        }

        const destination = self.graph.fields.items[fields.start];
        const pointer = switch (self.graph.types.items[@intFromEnum(destination.ty)]) {
            .pointer => |pointer_value| pointer_value,
            else => {
                if (trace) std.debug.print("[generic-init-probe-stage] module={} destination-not-pointer type={}\\n", .{ candidate_index, @intFromEnum(destination.ty) });
                return .{};
            },
        };
        if (!types.equal(self.graph, pointer.child, constructed_ty)) {
            if (trace) std.debug.print("[generic-init-probe-stage] module={} constructed-mismatch child={} wanted={}\\n", .{ candidate_index, @intFromEnum(pointer.child), @intFromEnum(constructed_ty) });
            return .{};
        }
'''
if text.count(old) != 1:
    raise RuntimeError(f"probeGenericInitializer stages anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

path.write_text(text)
subprocess.run(["zig", "fmt", str(path)], check=True)
