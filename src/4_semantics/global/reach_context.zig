const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");

pub const Context = union(enum) {
    module: Module,
    global: Global,

    pub const Module = struct {
        module: *const module_sg.ModuleSemanticGraph,
        offsets: globalizer.Offsets,
        visible_bindings: module_entities.BindingRange,
        owner_function: ?module_entities.ModuleFunctionId = null,
    };

    pub const Global = struct {
        visible_bindings: []const global_sg.GlobalBindingId,
        owner_function: ?global_sg.GlobalFunctionId = null,
    };

    pub fn fromModule(
        module: *const module_sg.ModuleSemanticGraph,
        offsets: globalizer.Offsets,
        visible_bindings: module_entities.BindingRange,
        owner_function: ?module_entities.ModuleFunctionId,
    ) Context {
        return .{ .module = .{
            .module = module,
            .offsets = offsets,
            .visible_bindings = visible_bindings,
            .owner_function = owner_function,
        } };
    }

    pub fn fromGlobal(
        visible_bindings: []const global_sg.GlobalBindingId,
        owner_function: ?global_sg.GlobalFunctionId,
    ) Context {
        return .{ .global = .{
            .visible_bindings = visible_bindings,
            .owner_function = owner_function,
        } };
    }

    pub fn bindingCount(self: Context) usize {
        return switch (self) {
            .module => |value| @intCast(value.visible_bindings.len),
            .global => |value| value.visible_bindings.len,
        };
    }

    pub fn bindingAt(self: Context, index: usize) global_sg.GlobalBindingId {
        return switch (self) {
            .module => |value| blk: {
                const start: usize = @intCast(value.visible_bindings.start);
                const local = value.module.semantic.binding_refs.items[start + index];
                break :blk globalizer.globalBinding(value.offsets, local);
            },
            .global => |value| value.visible_bindings[index],
        };
    }

    pub fn ownerFunction(self: Context) ?global_sg.GlobalFunctionId {
        return switch (self) {
            .module => |value| if (value.owner_function) |owner|
                globalizer.globalFunction(value.offsets, owner)
            else
                null,
            .global => |value| value.owner_function,
        };
    }
};

test "reach context preserves globalized lexical binding identity" {
    const std = @import("std");
    const binding: global_sg.GlobalBindingId = @enumFromInt(7);
    const context = Context.fromGlobal(&.{binding}, null);
    try std.testing.expectEqual(@as(usize, 1), context.bindingCount());
    try std.testing.expectEqual(binding, context.bindingAt(0));
    try std.testing.expect(context.ownerFunction() == null);
}
