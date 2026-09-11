const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const core_mod = @import("core.zig");
const types = @import("types.zig");

/// Resolves call syntax whose callee is a declared type. A visible `init`
/// whose first input is `$&ConstructedType` owns construction; only types with
/// no such initializer may fall back to direct structural initialization.
pub const Resolver = struct {
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,

    const InitializerLookup = struct {
        function: ?global_sg.GlobalFunctionId = null,
        has_visible_initializer: bool = false,
    };

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !?bool {
        return switch (operation) {
            .resolve_call => |value| @as(?bool, try self.resolveCall(module_index, module, o, value)),
            else => null,
        };
    }

    fn resolveCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        if (reference.generic_arguments != null) return false;

        const declaration_id = self.core.resolveDeclaration(module_index, reference, &.{.type}) catch return false;
        const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];
        const ty = declaration.type_id orelse return false;
        const input = globalizer.globalNode(o, value.input);

        const initializer = self.findInitializer(module_index, ty, input);
        if (initializer.function) |function_id| {
            const function = self.graph.functions.items[@intFromEnum(function_id)];
            const user_fields = global_sg.FieldRange{
                .start = function.input.start + 1,
                .len = function.input.len - 1,
            };
            if (!try self.core.completeCallInputFields(user_fields, input)) return false;
            const target = globalizer.globalNode(o, value.node);
            self.graph.nodes.items[@intFromEnum(target)] = .{
                .source = .{
                    .file_index = o.file_base + reference.source.file_index,
                    .offset = reference.source.offset,
                },
                .ty = ty,
                .content = .{ .type_initializer = .{
                    .type_decl = declaration_id,
                    .init_fn = function_id,
                    .args = input,
                } },
            };
            self.core.stats.calls += 1;
            return true;
        }

        // A visible initializer blocks field-wise construction even when the
        // provided arguments do not match it. That preserves the language's
        // encapsulation rule: private/invariant-bearing structs cannot bypass
        // their `init` merely because overload resolution failed.
        if (initializer.has_visible_initializer) return false;

        const fields = types.fields(self.graph, ty) orelse return false;
        if (self.core.scoreCallInput(fields, input) == null) return false;
        if (!try self.core.completeCallInputFields(fields, input)) return false;

        self.graph.nodes.items[@intFromEnum(input)].ty = ty;
        self.graph.nodes.items[@intFromEnum(input)].content.struct_value_literal.ty = ty;

        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = self.graph.nodes.items[@intFromEnum(input)];
        self.graph.nodes.items[@intFromEnum(target)].source = .{
            .file_index = o.file_base + reference.source.file_index,
            .offset = reference.source.offset,
        };
        self.core.stats.calls += 1;
        return true;
    }

    fn findInitializer(self: *Resolver, module_index: usize, constructed_ty: global_sg.GlobalTypeId, input: global_sg.GlobalNodeId) InitializerLookup {
        var result: InitializerLookup = .{};
        var best_score: u32 = 0;
        var tied = false;
        for (self.graph.functions.items, 0..) |function, raw| {
            if (function.input.len == 0) continue;
            const declaration = self.graph.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, self.graph.text(declaration.name), "init")) continue;
            if (!self.core.declarationVisible(module_index, function.declaration, null)) continue;

            const destination = self.graph.fields.items[function.input.start];
            const pointer = switch (self.graph.types.items[@intFromEnum(destination.ty)]) {
                .pointer => |value| value,
                else => continue,
            };
            if (!types.equal(self.graph, pointer.child, constructed_ty)) continue;
            result.has_visible_initializer = true;

            const user_fields = global_sg.FieldRange{
                .start = function.input.start + 1,
                .len = function.input.len - 1,
            };
            var score = self.core.scoreCallInput(user_fields, input) orelse continue;
            const owner = self.graph.moduleForDeclaration(function.declaration) orelse continue;
            if (@intFromEnum(owner) == module_index) score += 1;
            if (result.function == null or score > best_score) {
                result.function = @enumFromInt(@as(u32, @intCast(raw)));
                best_score = score;
                tied = false;
            } else if (score == best_score) {
                tied = true;
            }
        }
        if (tied) result.function = null;
        return result;
    }
};

test "declared type call materializes a struct value without visible init" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.init(allocator, false);
    defer fixture.deinit();

    try std.testing.expect((try fixture.resolve()).?);
    const result = fixture.graph.nodes.items[1];
    try std.testing.expectEqual(fixture.declared_type, result.ty.?);
    try std.testing.expectEqual(fixture.declared_type, result.content.struct_value_literal.ty);
}

test "declared type call dispatches through visible init" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.init(allocator, true);
    defer fixture.deinit();

    try std.testing.expect((try fixture.resolve()).?);
    const result = fixture.graph.nodes.items[1];
    try std.testing.expectEqual(fixture.declared_type, result.ty.?);
    try std.testing.expectEqual(@as(global_sg.GlobalDeclId, @enumFromInt(0)), result.content.type_initializer.type_decl);
    try std.testing.expectEqual(@as(global_sg.GlobalFunctionId, @enumFromInt(0)), result.content.type_initializer.init_fn);
    try std.testing.expectEqual(@as(global_sg.GlobalNodeId, @enumFromInt(0)), result.content.type_initializer.args);
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    graph: global_sg.GlobalSemanticGraph,
    module: module_sg.ModuleSemanticGraph,
    offsets: [1]globalizer.Offsets,
    declared_type: global_sg.GlobalTypeId,

    fn init(allocator: std.mem.Allocator, with_initializer: bool) !Fixture {
        var graph: global_sg.GlobalSemanticGraph = .{};
        errdefer graph.deinit(allocator);
        var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "app") };
        errdefer module.deinit(allocator);

        try module.strings.appendSlice(allocator, "Packet");
        try module.semantic.external_refs.append(allocator, .{
            .kind = .function,
            .module_path = null,
            .name = .{ .start = 0, .len = 6 },
            .source = .{ .file_index = 0, .offset = 17 },
        });

        const declaration_name = try graph.addString(allocator, "Packet");
        const module_dir = try graph.addString(allocator, "app");
        const declared_type: global_sg.GlobalTypeId = @enumFromInt(0);
        const input_type: global_sg.GlobalTypeId = @enumFromInt(1);
        try graph.declarations.append(allocator, .{
            .kind = .type,
            .name = declaration_name,
            .source = .{ .file_index = 0, .offset = 0 },
            .type_id = declared_type,
            .struct_fields = .{ .start = 0, .len = 0 },
        });
        try graph.types.append(allocator, .{ .declared = @as(global_sg.GlobalDeclId, @enumFromInt(0)) });
        try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } });

        if (with_initializer) {
            const pointer_type: global_sg.GlobalTypeId = @enumFromInt(2);
            try graph.types.append(allocator, .{ .pointer = .{ .child = declared_type, .mutability = .read_write } });
            const p_name = try graph.addString(allocator, "p");
            try graph.fields.append(allocator, .{
                .name = p_name,
                .ty = pointer_type,
                .source = .{ .file_index = 0, .offset = 3 },
            });
            const init_name = try graph.addString(allocator, "init");
            try graph.declarations.append(allocator, .{
                .kind = .function,
                .name = init_name,
                .source = .{ .file_index = 0, .offset = 2 },
                .function_id = @enumFromInt(0),
            });
            try graph.functions.append(allocator, .{
                .declaration = @enumFromInt(1),
                .input = .{ .start = 0, .len = 1 },
                .output = .{ .start = 1, .len = 0 },
            });
        }

        try graph.modules.append(allocator, .{
            .dir = module_dir,
            .files = .{ .start = 0, .len = 0 },
            .declarations = .{ .start = 0, .len = if (with_initializer) 2 else 1 },
        });
        try graph.nodes.append(allocator, .{
            .source = .{ .file_index = 0, .offset = 18 },
            .ty = input_type,
            .content = .{ .struct_value_literal = .{
                .fields = .{ .start = 0, .len = 0 },
                .ty = input_type,
            } },
        });
        try graph.nodes.append(allocator, .{
            .source = .{ .file_index = 0, .offset = 19 },
            .ty = input_type,
            .content = .{ .bool_literal = false },
        });

        return .{
            .allocator = allocator,
            .graph = graph,
            .module = module,
            .offsets = .{emptyOffsets()},
            .declared_type = declared_type,
        };
    }

    fn deinit(self: *Fixture) void {
        self.graph.deinit(self.allocator);
        self.module.deinit(self.allocator);
    }

    fn resolve(self: *Fixture) !?bool {
        var core = core_mod.Resolver{
            .allocator = self.allocator,
            .graph = &self.graph,
            .modules = self.modules(),
            .offsets = &self.offsets,
        };
        var resolver: Resolver = .{
            .graph = &self.graph,
            .modules = self.modules(),
            .offsets = &self.offsets,
            .core = &core,
        };
        const operation = module_entities.PendingOperation{ .resolve_call = .{
            .node = @enumFromInt(1),
            .callee = @enumFromInt(0),
            .input = @enumFromInt(0),
        } };
        return resolver.tryResolve(0, &self.module, self.offsets[0], operation);
    }

    fn modules(self: *Fixture) []const module_sg.ModuleSemanticGraph {
        return @as([*]const module_sg.ModuleSemanticGraph, @ptrCast(&self.module))[0..1];
    }
};

fn emptyOffsets() globalizer.Offsets {
    return .{
        .file_base = 0,
        .declaration_base = 0,
        .type_base = 0,
        .function_base = 0,
        .field_base = 0,
        .variant_base = 0,
        .generic_argument_base = 0,
        .binding_base = 0,
        .node_base = 0,
        .block_base = 0,
        .value_field_base = 0,
        .switch_case_base = 0,
        .switch_base = 0,
        .auto_deinit_field_base = 0,
        .auto_deinit_base = 0,
        .virtual_registry_base = 0,
        .virtualize_base = 0,
        .virtual_call_base = 0,
        .reach_segment_base = 0,
        .reach_alternative_base = 0,
        .reach_base = 0,
        .nullable_unwrap_base = 0,
        .testing_expect_error_base = 0,
        .error_propagation_base = 0,
        .error_context_base = 0,
        .node_ref_base = 0,
        .type_ref_base = 0,
        .binding_ref_base = 0,
        .function_ref_base = 0,
        .virtual_registry_ref_base = 0,
        .symbol_declaration_base = 0,
        .string_base = 0,
    };
}
