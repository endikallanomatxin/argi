const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const Fields = @import("../primitives/schema.zig").Range(global_sg.GlobalValueFieldId);

/// Borrowed lexical facts for ordinary input defaults and cleanup. Calls never
/// search these bindings to acquire dependencies or extend a caller's signature.
pub const Context = struct {
    owner_function: ?global_sg.GlobalFunctionId,
    assumed_fields: Fields = .{ .start = 0, .len = 0 },
    // Session cleanup needs shadowing information when inheriting assumptions
    // from earlier commands. Ordinary calls need only their supplied fields.
    visible_bindings: []const global_sg.GlobalBindingId = &.{},

    pub fn fromModule(offsets: globalizer.Offsets, owner: ?module_entities.ModuleFunctionId) Context {
        return .{ .owner_function = if (owner) |id| globalizer.globalFunction(offsets, id) else null };
    }

    pub fn fromGlobal(visible: []const global_sg.GlobalBindingId, owner: ?global_sg.GlobalFunctionId) Context {
        return .{ .visible_bindings = visible, .owner_function = owner };
    }

    pub fn assumedFields(self: Context) Fields {
        return self.assumed_fields;
    }

    pub fn withAssumedFields(self: Context, fields: Fields) Context {
        var result = self;
        result.assumed_fields = fields;
        return result;
    }

    pub fn ownerFunction(self: Context) ?global_sg.GlobalFunctionId {
        return self.owner_function;
    }
};

test "call context preserves borrowed cleanup bindings and lexical defaults" {
    const std = @import("std");
    const binding: global_sg.GlobalBindingId = @enumFromInt(7);
    const context = Context.fromGlobal(&.{binding}, null);
    const completed = context.withAssumedFields(.{ .start = 3, .len = 2 });
    try std.testing.expectEqual(binding, completed.visible_bindings[0]);
    try std.testing.expectEqual(@as(u32, 3), completed.assumedFields().start);
    try std.testing.expectEqual(@as(u32, 2), completed.assumedFields().len);
    try std.testing.expectEqual(@as(u32, 0), context.assumedFields().len);
    try std.testing.expect(completed.ownerFunction() == null);
}
