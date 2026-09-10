const primitives = @import("schema.zig");

/// Materialized representation of a generic identity. `SemanticType.generic`
/// keeps canonical identity (`base + arguments`); this table records the shape
/// consumers need without re-instantiating the parameterized.
pub fn GenericInstanceShape(comptime Ids: type) type {
    return union(enum) {
        structure: struct {
            fields: primitives.Range(Ids.FieldId),
            layout: primitives.StructLayout = .regular,
        },
        choice: struct {
            variants: primitives.Range(Ids.VariantId),
            layout: primitives.ChoiceLayout = .regular,
        },
        array: struct {
            length: u64,
            element: Ids.TypeId,
        },
        /// Generic aliases/special forms may canonicalize to another type.
        alias: Ids.TypeId,
    };
}

pub fn GenericInstance(comptime Ids: type) type {
    return struct {
        type_id: Ids.TypeId,
        shape: GenericInstanceShape(Ids),
    };
}

test "generic instance shape keeps identity separate from materialization" {
    const Ids = struct {
        pub const TypeId = enum(u32) { _ };
        pub const FieldId = enum(u32) { _ };
        pub const VariantId = enum(u32) { _ };
    };
    const Instance = GenericInstance(Ids);
    const value = Instance{
        .type_id = @enumFromInt(3),
        .shape = .{ .array = .{ .length = 8, .element = @enumFromInt(1) } },
    };
    try @import("std").testing.expectEqual(@as(u64, 8), value.shape.array.length);
}
