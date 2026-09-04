const std = @import("std");
const source_db = @import("../1_base/source_db.zig");
const token = @import("../2_tokens/token.zig");

pub const TokenIndex = enum(u32) { _ };
pub const ExtraIndex = enum(u32) { _ };

pub const NodeIndex = enum(u32) {
    _,

    pub fn optional(index: NodeIndex) OptionalNodeIndex {
        const result: OptionalNodeIndex = @enumFromInt(@intFromEnum(index));
        std.debug.assert(result != .none);
        return result;
    }
};

pub const OptionalNodeIndex = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn init(index: ?NodeIndex) OptionalNodeIndex {
        return if (index) |value| value.optional() else .none;
    }

    pub fn unwrap(index: OptionalNodeIndex) ?NodeIndex {
        return if (index == .none) null else @enumFromInt(@intFromEnum(index));
    }
};

pub const SyntaxRef = struct {
    file_id: source_db.FileId,
    node: NodeIndex,
};

pub const SubRange = extern struct {
    start: ExtraIndex,
    end: ExtraIndex,
};

/// The tag is the schema for `data`; `Data` deliberately has no runtime tag.
/// Keeping these as separate MultiArrayList columns makes the fixed storage
/// cost 13 bytes per node regardless of the host ABI's struct padding.
pub const Node = struct {
    tag: Tag,
    main_token: TokenIndex,
    data: Data,

    pub const Tag = enum(u8) {
        choice_option_declaration,
        symbol_declaration_constant,
        symbol_declaration_variable,
        type_declaration,
        c_enum_declaration,
        c_union_declaration,
        abstract_declaration,
        abstract_implements,
        abstract_defaultsto,
        abstract_function_requirement,
        function_declaration,
        function_declaration_once,
        test_declaration,
        assignment,
        expression_statement,
        identifier,
        pipe_placeholder,
        reach_directive,
        reach_alternative,
        move_expression,
        function_call,
        pipe_expression,
        code_block,
        literal,
        list_literal,
        struct_type_literal,
        struct_type_field,
        choice_type_literal,
        choice_type_variant,
        struct_value_literal,
        struct_value_field,
        positional_value_field,
        choice_literal,
        struct_field_access,
        choice_payload_access,
        error_propagation,
        error_context,
        index_access,
        return_statement,
        break_statement,
        continue_statement,
        binary_add,
        binary_subtract,
        binary_multiply,
        binary_divide,
        binary_modulo,
        compare_equal,
        compare_not_equal,
        compare_less,
        compare_greater,
        compare_less_equal,
        compare_greater_equal,
        logical_and,
        logical_or,
        if_statement,
        for_statement,
        while_statement,
        match_statement,
        match_case,
        import_statement,
        defer_statement,
        keep_statement,
        index_assignment,
        address_of,
        address_of_mut,
        dereference,
        pointer_assignment,
        type_name,
        pointer_type,
        pointer_type_mut,
        inferred_errable_type,
        array_type,
        generic_type_instantiation,
    };

    pub const Data = extern union {
        node: NodeIndex,
        optional_node: OptionalNodeIndex,
        token: TokenIndex,
        extra: ExtraIndex,
        node_and_node: extern struct { first: NodeIndex, second: NodeIndex },
        node_and_optional: extern struct { node: NodeIndex, optional: OptionalNodeIndex },
        node_and_extra: extern struct { node: NodeIndex, extra: ExtraIndex },
        extra_and_node: extern struct { extra: ExtraIndex, node: NodeIndex },
        token_and_node: extern struct { token: TokenIndex, node: NodeIndex },
        token_and_token: extern struct { first: TokenIndex, second: TokenIndex },
        extra_range: SubRange,
    };
};

pub const TokenList = std.MultiArrayList(token.Token);
pub const NodeList = std.MultiArrayList(Node);

pub const SyntaxFile = struct {
    file_id: source_db.FileId,
    tokens: TokenList = .empty,
    nodes: NodeList = .empty,
    extra_data: std.ArrayList(u32) = .empty,
    roots: std.ArrayList(NodeIndex) = .empty,

    pub fn deinit(tree: *SyntaxFile, allocator: std.mem.Allocator) void {
        tree.tokens.deinit(allocator);
        tree.nodes.deinit(allocator);
        tree.extra_data.deinit(allocator);
        tree.roots.deinit(allocator);
        tree.* = undefined;
    }

    pub fn addNode(tree: *SyntaxFile, allocator: std.mem.Allocator, node: Node) !NodeIndex {
        if (tree.nodes.len >= std.math.maxInt(u32)) return error.SyntaxTreeTooLarge;
        const index: NodeIndex = @enumFromInt(@as(u32, @intCast(tree.nodes.len)));
        try tree.nodes.append(allocator, node);
        return index;
    }

    pub fn addExtra(tree: *SyntaxFile, allocator: std.mem.Allocator, value: anytype) !ExtraIndex {
        const fields = std.meta.fields(@TypeOf(value));
        if (tree.extra_data.items.len + fields.len > std.math.maxInt(u32)) return error.SyntaxTreeTooLarge;
        try tree.extra_data.ensureUnusedCapacity(allocator, fields.len);
        const index: ExtraIndex = @enumFromInt(@as(u32, @intCast(tree.extra_data.items.len)));
        inline for (fields) |field| {
            tree.extra_data.appendAssumeCapacity(encodeExtraField(field.type, @field(value, field.name)));
        }
        return index;
    }

    pub fn extraData(tree: *const SyntaxFile, comptime T: type, index: ExtraIndex) T {
        var result: T = undefined;
        inline for (std.meta.fields(T), 0..) |field, offset| {
            const word = tree.extra_data.items[@intFromEnum(index) + offset];
            @field(result, field.name) = decodeExtraField(field.type, word);
        }
        return result;
    }

    pub fn addNodeRange(tree: *SyntaxFile, allocator: std.mem.Allocator, values: []const NodeIndex) !SubRange {
        if (tree.extra_data.items.len + values.len > std.math.maxInt(u32)) return error.SyntaxTreeTooLarge;
        try tree.extra_data.ensureUnusedCapacity(allocator, values.len);
        const start: ExtraIndex = @enumFromInt(@as(u32, @intCast(tree.extra_data.items.len)));
        for (values) |value| tree.extra_data.appendAssumeCapacity(@intFromEnum(value));
        return .{
            .start = start,
            .end = @enumFromInt(@as(u32, @intCast(tree.extra_data.items.len))),
        };
    }

    pub fn nodeRange(tree: *const SyntaxFile, range: SubRange) []const NodeIndex {
        return @ptrCast(tree.extra_data.items[@intFromEnum(range.start)..@intFromEnum(range.end)]);
    }

    pub fn tag(tree: *const SyntaxFile, index: NodeIndex) Node.Tag {
        return tree.nodes.items(.tag)[@intFromEnum(index)];
    }

    pub fn mainToken(tree: *const SyntaxFile, index: NodeIndex) TokenIndex {
        return tree.nodes.items(.main_token)[@intFromEnum(index)];
    }

    pub fn data(tree: *const SyntaxFile, index: NodeIndex) Node.Data {
        return tree.nodes.items(.data)[@intFromEnum(index)];
    }

    pub fn location(tree: *const SyntaxFile, index: NodeIndex) token.Location {
        return tree.tokens.items(.location)[@intFromEnum(tree.mainToken(index))];
    }

    pub fn tokenText(tree: *const SyntaxFile, db: *const source_db.SourceDb, index: TokenIndex) []const u8 {
        const token_index: usize = @intFromEnum(index);
        const contents = tree.tokens.items(.content)[token_index];
        const source = db.get(tree.file_id).source;
        return switch (contents) {
            .identifier, .comment => |range| range.slice(source),
            .literal => |literal| switch (literal) {
                .decimal_int_literal,
                .hexadecimal_int_literal,
                .octal_int_literal,
                .binary_int_literal,
                .regular_float_literal,
                .scientific_float_literal,
                .string_literal,
                => |range| range.slice(source),
                .bool_literal => |value| if (value) "true" else "false",
                .char_literal => source[tree.tokens.items(.location)[token_index].offset..][0..3],
            },
            else => "",
        };
    }
};

fn encodeExtraField(comptime T: type, value: T) u32 {
    return switch (@typeInfo(T)) {
        .@"enum" => @intFromEnum(value),
        .int => @intCast(value),
        else => @compileError("extra_data fields must be u32-sized indices or integers"),
    };
}

fn decodeExtraField(comptime T: type, value: u32) T {
    return switch (@typeInfo(T)) {
        .@"enum" => @enumFromInt(value),
        .int => @intCast(value),
        else => @compileError("extra_data fields must be u32-sized indices or integers"),
    };
}

test "compact syntax indices reserve the optional sentinel" {
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(NodeIndex));
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(TokenIndex));
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(ExtraIndex));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(Node.Data));
    try std.testing.expectEqual(OptionalNodeIndex.none, OptionalNodeIndex.init(null));
    const node: NodeIndex = @enumFromInt(7);
    try std.testing.expectEqual(node, OptionalNodeIndex.init(node).unwrap().?);
}

test "compact syntax stores typed extras and node ranges" {
    const Extra = struct { first: NodeIndex, second: OptionalNodeIndex, token_index: TokenIndex };
    var tree: SyntaxFile = .{ .file_id = @enumFromInt(0) };
    defer tree.deinit(std.testing.allocator);

    const first: NodeIndex = @enumFromInt(2);
    const second: NodeIndex = @enumFromInt(5);
    const extra_index = try tree.addExtra(std.testing.allocator, Extra{
        .first = first,
        .second = second.optional(),
        .token_index = @enumFromInt(9),
    });
    try std.testing.expectEqual(first, tree.extraData(Extra, extra_index).first);

    const range = try tree.addNodeRange(std.testing.allocator, &.{ first, second });
    try std.testing.expectEqualSlices(NodeIndex, &.{ first, second }, tree.nodeRange(range));
}
