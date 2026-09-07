const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const semantic_strings = @import("semantic_strings.zig");

pub const StringRange = semantic_strings.StringRange;

pub fn Range(comptime Id: type) type {
    return struct {
        start: u32,
        len: u32,

        pub fn at(self: @This(), index: u32) Id {
            std.debug.assert(index < self.len);
            return @enumFromInt(self.start + index);
        }
    };
}

pub const BuiltinType = enum {
    Int8,
    Int16,
    Int32,
    Int64,
    UIntNative,
    UInt8,
    UInt16,
    UInt32,
    UInt64,
    Float16,
    Float32,
    Float64,
    Char,
    Bool,
    Void,
    Type,
    Any,
};

pub const DeclarationKind = enum {
    binding,
    import_alias,
    abstract_type,
    type,
    choice_option,
    function,
    test_function,
};

pub const SafetyPrimitive = enum {
    none,
    establish_fresh_reference,
    establish_inherited_reference,
    establish_inherited_storage,
    establish_allocation,
    raw_allocated_storage,
    reference_offset,
    mutable_reference_offset,
    reinterpret_reference,
    mutable_reinterpret_reference,
    read_reference,
    restrict_reference,
    trusted_opaque_move,
    trusted_opaque_move_in,
    trusted_opaque_move_out,
    trusted_opaque_relocate,
    trusted_opaque_drop,
    trusted_opaque_mark_empty,
    relocate,
};

pub const FunctionFlags = packed struct(u16) {
    is_once: bool = false,
    is_test: bool = false,
    has_declared_body: bool = false,
    uses_inferred_error_reasons: bool = false,
    is_deinit: bool = false,
    is_generic_instantiation: bool = false,
    is_abstract_dispatch: bool = false,
    _padding: u9 = 0,
};

pub const StructLayout = enum(u8) { regular, c_union };
pub const ChoiceLayout = enum(u8) { regular, c_enum };
pub const LogicalOperator = enum(u8) { and_, or_ };

pub const SourceRef = struct {
    file_index: u32,
    offset: u32,
};

pub fn SemanticType(comptime TypeId: type, comptime DeclId: type, comptime FieldId: type, comptime GenericArgId: type) type {
    return union(enum) {
        builtin: BuiltinType,
        declared: DeclId,
        pointer: struct { child: TypeId, mutability: syn.PointerMutability },
        array: struct { length: u64, element: TypeId },
        nullable: TypeId,
        inferred_errable: TypeId,
        structural: Range(FieldId),
        structural_choice: Range(FieldId),
        generic: struct { base: DeclId, arguments: Range(GenericArgId) },
    };
}

pub fn Field(comptime TypeId: type, comptime NodeId: type) type {
    return struct {
        name: StringRange,
        ty: TypeId,
        source: SourceRef,
        default_value: ?NodeId = null,
    };
}

pub fn ChoiceVariant(comptime TypeId: type, comptime DeclId: type) type {
    return struct {
        name: StringRange,
        payload_type: ?TypeId,
        option_decl: ?DeclId = null,
        source: SourceRef,
        value: i32,
    };
}

pub fn GenericTypeArgument(comptime TypeId: type) type {
    return struct {
        name: StringRange,
        ty: TypeId,
    };
}

pub fn Function(comptime DeclId: type, comptime FieldId: type, comptime BlockId: type, comptime BindingId: type, comptime TypeId: type) type {
    return struct {
        declaration: DeclId,
        input: Range(FieldId),
        output: Range(FieldId),
        body: ?BlockId = null,
        input_bindings: Range(BindingId) = .{ .start = 0, .len = 0 },
        output_bindings: Range(BindingId) = .{ .start = 0, .len = 0 },
        inferred_error_reasons: ?TypeId = null,
        safety_primitive: SafetyPrimitive = .none,
        flags: FunctionFlags = .{},
    };
}

pub fn Binding(comptime TypeId: type, comptime NodeId: type) type {
    return struct {
        name: StringRange,
        source: SourceRef,
        ty: TypeId,
        initialization: ?NodeId = null,
        mutability: syn.Mutability,
    };
}

pub fn Block(comptime NodeId: type) type {
    return struct {
        nodes: Range(NodeId),
        ret_val: ?NodeId = null,
    };
}

pub fn Node(comptime NodeId: type, comptime TypeId: type, comptime DeclId: type, comptime FunctionId: type, comptime BindingId: type, comptime BlockId: type, comptime FieldId: type, comptime VariantId: type) type {
    return struct {
        source: SourceRef,
        ty: ?TypeId,
        content: Content,

        pub const Content = union(enum) {
            declaration: DeclId,
            binding_declaration: BindingId,
            binding_use: BindingId,
            move_value: NodeId,
            assignment: struct { binding: BindingId, value: NodeId },
            function_call: struct { callee: FunctionId, input: NodeId },
            code_block: BlockId,
            int_literal: i64,
            float_literal: f64,
            char_literal: u8,
            string_literal: StringRange,
            bool_literal: bool,
            list_literal: Range(NodeId),
            struct_value_literal: Range(FieldId),
            struct_field_access: struct { value: NodeId, field_index: u32 },
            choice_literal: struct { variant: VariantId, payload: ?NodeId },
            choice_payload_access: struct { value: NodeId, variant: VariantId },
            array_literal: Range(NodeId),
            array_index: struct { value: NodeId, index: NodeId },
            array_store: struct { value: NodeId, index: NodeId, stored: NodeId },
            struct_field_store: struct { value: NodeId, field_index: u32, stored: NodeId },
            binary_operation: struct { operator: tok.BinaryOperator, left: NodeId, right: NodeId },
            comparison: struct { operator: tok.ComparisonOperator, left: NodeId, right: NodeId },
            logical_operation: struct { operator: LogicalOperator, left: NodeId, right: NodeId },
            return_statement: struct { expression: ?NodeId, cleanup: Range(NodeId) },
            if_statement: struct { condition: NodeId, then_block: BlockId, else_block: ?BlockId },
            while_statement: struct { condition: NodeId, body: BlockId },
            for_statement: struct { init: ?NodeId, condition: NodeId, increment: ?NodeId, body: BlockId },
            switch_statement: struct { expression: NodeId, cases: Range(NodeId), default_block: ?BlockId, exhaustive: bool },
            break_statement,
            continue_statement,
            address_of: NodeId,
            dereference: NodeId,
            pointer_assignment: struct { pointer: NodeId, value: NodeId },
            type_literal: TypeId,
            explicit_cast: struct { value: NodeId, target_type: TypeId },
        };
    };
}

test "semantic primitives preserve distinct id domains" {
    const ModuleNodeId = enum(u32) { _ };
    const GlobalNodeId = enum(u32) { _ };
    const ModuleTypeId = enum(u32) { _ };
    const ModuleDeclId = enum(u32) { _ };
    const ModuleFieldId = enum(u32) { _ };
    const ModuleArgId = enum(u32) { _ };

    const ModuleType = SemanticType(ModuleTypeId, ModuleDeclId, ModuleFieldId, ModuleArgId);
    const pointer = ModuleType{ .pointer = .{ .child = @enumFromInt(3), .mutability = .constant } };
    try std.testing.expectEqual(@as(u32, 3), @intFromEnum(pointer.pointer.child));
    try std.testing.expect(ModuleNodeId != GlobalNodeId);
}
