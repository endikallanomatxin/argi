const global_sg = @import("graph.zig");
const core_mod = @import("core.zig");
const abstract_mod = @import("abstracts.zig");

/// Additional call compatibility owned above Core. Core handles structural
/// compatibility; this policy adds the language-level concrete-to-abstract
/// relation without making Core depend on the abstract resolver.
pub const Abstract = struct {
    core: *const core_mod.Resolver,
    abstracts: *abstract_mod.Resolver,

    pub fn compatible(self: @This(), actual: global_sg.GlobalTypeId, expected: global_sg.GlobalTypeId) bool {
        const actual_pointer = switch (self.core.graph.types.items[@intFromEnum(actual)]) {
            .pointer => |pointer| pointer,
            else => return false,
        };
        const expected_pointer = switch (self.core.graph.types.items[@intFromEnum(expected)]) {
            .pointer => |pointer| pointer,
            else => return false,
        };
        if (expected_pointer.mutability == .read_write and actual_pointer.mutability != .read_write) return false;
        return self.abstracts.concreteImplements(actual_pointer.child, expected_pointer.child);
    }
};
