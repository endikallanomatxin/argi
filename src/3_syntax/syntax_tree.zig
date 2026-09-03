const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const source_db = @import("../1_base/source_db.zig");

pub const TokenIndex = u32;
pub const ExtraIndex = enum(u32) { _ };
pub const Mutability = enum { constant, variable };
pub const PointerMutability = enum { read_only, read_write };

pub const NodeIndex = enum(u32) {
    _,

    pub fn toOptional(index: NodeIndex) OptionalNodeIndex {
        const result: OptionalNodeIndex = @enumFromInt(@intFromEnum(index));
        std.debug.assert(result != .none);
        return result;
    }
};

pub const OptionalNodeIndex = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn fromOptional(index: ?NodeIndex) OptionalNodeIndex {
        return if (index) |value| value.toOptional() else .none;
    }

    pub fn unwrap(index: OptionalNodeIndex) ?NodeIndex {
        return if (index == .none) null else @enumFromInt(@intFromEnum(index));
    }
};

pub const SyntaxRef = struct {
    file_id: source_db.FileId,
    node: NodeIndex,
};

pub fn fileForRef(files: []const SyntaxFile, ref_value: SyntaxRef) *const SyntaxFile {
    for (files) |*file| {
        if (file.file_id == ref_value.file_id) return file;
    }
    unreachable;
}

// Transitional aliases used only while consumers are being moved to typed
// accessors. They do not describe stored nodes and must disappear with the
// remaining legacy consumer signatures.
pub const STNode = SyntaxRef;
pub const Type = SyntaxRef;
pub const StructTypeLiteral = NodeIndex;
pub const StructTypeLiteralField = NodeIndex;

pub const TokenList = std.MultiArrayList(tok.Token);
pub const NodeList = std.MultiArrayList(Node);

pub const SyntaxFile = struct {
    file_id: source_db.FileId,
    source: []const u8,
    tokens: TokenList,
    nodes: NodeList,
    extra_data: std.ArrayList(u32),
    roots: []NodeIndex = &.{},

    pub fn init(allocator: std.mem.Allocator, file_id: source_db.FileId, source: []const u8, tokens: []const tok.Token) !SyntaxFile {
        var token_list: TokenList = .empty;
        errdefer token_list.deinit(allocator);
        try token_list.ensureTotalCapacity(allocator, tokens.len);
        for (tokens) |token_value| token_list.appendAssumeCapacity(token_value);
        return .{
            .file_id = file_id,
            .source = source,
            .tokens = token_list,
            .nodes = .empty,
            .extra_data = .empty,
        };
    }

    pub fn deinit(self: *SyntaxFile, allocator: std.mem.Allocator) void {
        allocator.free(self.roots);
        self.tokens.deinit(allocator);
        self.nodes.deinit(allocator);
        self.extra_data.deinit(allocator);
        self.* = undefined;
    }

    pub fn token(self: *const SyntaxFile, index: TokenIndex) tok.Token {
        return self.tokens.get(index);
    }

    pub fn tokenLocation(self: *const SyntaxFile, index: TokenIndex) tok.Location {
        return self.tokens.items(.location)[index];
    }

    pub fn tokenText(self: *const SyntaxFile, index: TokenIndex) []const u8 {
        const token_value = self.token(index);
        return switch (token_value.content) {
            .identifier, .comment => |range| range.slice(self.source),
            .literal => |literal| switch (literal) {
                .decimal_int_literal,
                .hexadecimal_int_literal,
                .octal_int_literal,
                .binary_int_literal,
                .regular_float_literal,
                .scientific_float_literal,
                .string_literal,
                => |range| range.slice(self.source),
                .bool_literal => |value| if (value) "true" else "false",
                .char_literal => self.source[token_value.location.offset .. token_value.location.offset + 3],
            },
            else => tokenLexeme(token_value.content),
        };
    }

    pub fn nodeTag(self: *const SyntaxFile, index: NodeIndex) Node.Tag {
        return self.nodes.items(.tag)[@intFromEnum(index)];
    }

    pub fn nodeMainToken(self: *const SyntaxFile, index: NodeIndex) TokenIndex {
        return self.nodes.items(.main_token)[@intFromEnum(index)];
    }

    pub fn nodeData(self: *const SyntaxFile, index: NodeIndex) Node.Data {
        return self.nodes.items(.data)[@intFromEnum(index)];
    }

    pub fn nodeLocation(self: *const SyntaxFile, index: NodeIndex) tok.Location {
        return self.tokenLocation(self.nodeMainToken(index));
    }

    pub fn declarationNameToken(self: *const SyntaxFile, node: NodeIndex) ?TokenIndex {
        return switch (self.nodeTag(node)) {
            .choice_option_declaration => self.nodeData(node).token,
            .symbol_declaration_constant,
            .symbol_declaration_variable,
            .type_declaration,
            .c_enum_declaration,
            .c_union_declaration,
            .abstract_declaration,
            .abstract_implements,
            .abstract_defaultsto,
            .function_declaration,
            .function_declaration_once,
            .test_declaration,
            => self.nodeMainToken(node),
            else => null,
        };
    }

    pub fn ref(self: *const SyntaxFile, node: NodeIndex) SyntaxRef {
        return .{ .file_id = self.file_id, .node = node };
    }

    pub fn extraData(self: *const SyntaxFile, comptime T: type, index: ExtraIndex) T {
        const fields = std.meta.fields(T);
        var result: T = undefined;
        inline for (fields, 0..) |field, offset| {
            const raw = self.extra_data.items[@intFromEnum(index) + offset];
            @field(result, field.name) = decodeExtraField(field.type, raw);
        }
        return result;
    }

    pub fn extraNodeSlice(self: *const SyntaxFile, range: SubRange) []const NodeIndex {
        return @ptrCast(self.extra_data.items[@intFromEnum(range.start)..@intFromEnum(range.end)]);
    }

    pub fn fullFunction(self: *const SyntaxFile, node: NodeIndex) ?FullFunction {
        return switch (self.nodeTag(node)) {
            .function_declaration, .function_declaration_once, .test_declaration => blk: {
                const extra = self.extraData(FunctionExtra, self.nodeData(node).extra);
                break :blk .{
                    .name_token = self.nodeMainToken(node),
                    .generic_params = self.extraNodeSlice(extra.genericParams()),
                    .generic_params_struct = extra.generic_params_struct.unwrap(),
                    .input = extra.input,
                    .output = extra.output,
                    .body = extra.body.unwrap(),
                    .is_once = self.nodeTag(node) == .function_declaration_once,
                    .is_test = self.nodeTag(node) == .test_declaration,
                };
            },
            else => null,
        };
    }

    pub fn fullIf(self: *const SyntaxFile, node: NodeIndex) ?FullIf {
        if (self.nodeTag(node) != .if_statement) return null;
        const data = self.nodeData(node).node_and_extra;
        const extra = self.extraData(IfExtra, data[1]);
        return .{ .condition = data[0], .then_block = extra.then_block, .else_block = extra.else_block.unwrap() };
    }

    pub fn fullCall(self: *const SyntaxFile, node: NodeIndex) ?FullCall {
        if (self.nodeTag(node) != .function_call) return null;
        const extra = self.extraData(CallExtra, self.nodeData(node).extra);
        return .{
            .callee_token = self.nodeMainToken(node),
            .module_qualifier_token = extra.module_qualifier_token,
            .type_arguments = self.extraNodeSlice(extra.typeArguments()),
            .type_arguments_struct = extra.type_arguments_struct.unwrap(),
            .input = extra.input,
        };
    }

    pub fn fullStructType(self: *const SyntaxFile, node: NodeIndex) ?FullStructType {
        if (self.nodeTag(node) != .struct_type_literal) return null;
        return .{ .fields = self.extraNodeSlice(self.nodeData(node).extra_range) };
    }

    pub fn fullField(self: *const SyntaxFile, node: NodeIndex) ?FullField {
        return switch (self.nodeTag(node)) {
            .struct_type_field, .inferred_result_field => blk: {
                const extra = self.extraData(FieldExtra, self.nodeData(node).extra);
                break :blk .{
                    .name_token = self.nodeMainToken(node),
                    .type_node = extra.type_node.unwrap(),
                    .default_value = extra.default_value.unwrap(),
                    .is_inferred_result = self.nodeTag(node) == .inferred_result_field,
                };
            },
            else => null,
        };
    }

    pub fn fullSymbol(self: *const SyntaxFile, node: NodeIndex) ?FullSymbol {
        return switch (self.nodeTag(node)) {
            .symbol_declaration_constant, .symbol_declaration_variable => blk: {
                const extra = self.extraData(FieldExtra, self.nodeData(node).extra);
                break :blk .{
                    .name_token = self.nodeMainToken(node),
                    .type_node = extra.type_node.unwrap(),
                    .value = extra.default_value.unwrap(),
                    .mutability = if (self.nodeTag(node) == .symbol_declaration_variable) .variable else .constant,
                };
            },
            else => null,
        };
    }

    pub fn fullGenericValue(self: *const SyntaxFile, node: NodeIndex) ?FullGenericValue {
        return switch (self.nodeTag(node)) {
            .type_declaration, .c_enum_declaration, .c_union_declaration, .abstract_implements, .abstract_defaultsto => blk: {
                const extra = self.extraData(GenericValueExtra, self.nodeData(node).extra);
                break :blk .{
                    .name_token = self.nodeMainToken(node),
                    .generic_params = self.extraNodeSlice(.{ .start = extra.generic_params_start, .end = extra.generic_params_end }),
                    .generic_params_struct = extra.generic_params_struct.unwrap(),
                    .value = extra.value,
                };
            },
            else => null,
        };
    }

    pub fn fullAbstract(self: *const SyntaxFile, node: NodeIndex) ?FullAbstract {
        if (self.nodeTag(node) != .abstract_declaration) return null;
        const extra = self.extraData(AbstractExtra, self.nodeData(node).extra);
        return .{
            .name_token = self.nodeMainToken(node),
            .generic_params = self.extraNodeSlice(.{ .start = extra.generic_params_start, .end = extra.generic_params_end }),
            .generic_params_struct = extra.generic_params_struct.unwrap(),
            .requires_abstracts = self.extraNodeSlice(.{ .start = extra.requires_abstracts_start, .end = extra.requires_abstracts_end }),
            .requires_functions = self.extraNodeSlice(.{ .start = extra.requires_functions_start, .end = extra.requires_functions_end }),
        };
    }

    pub fn fullType(self: *const SyntaxFile, node: NodeIndex) ?FullType {
        return switch (self.nodeTag(node)) {
            .type_name => .{ .name = .{
                .name_token = self.nodeMainToken(node),
                .qualifier_token = optionalToken(self.nodeData(node).token_and_token[1]),
            } },
            .pointer_type => .{ .pointer = .{ .child = self.nodeData(node).node, .mutability = .read_only } },
            .pointer_type_mut => .{ .pointer = .{ .child = self.nodeData(node).node, .mutability = .read_write } },
            .nullable_type => .{ .nullable = self.nodeData(node).node },
            .inferred_errable_type => .{ .inferred_errable = self.nodeData(node).node },
            .array_type => .{ .array = .{
                .length_token = self.nodeData(node).token_and_node[0],
                .element = self.nodeData(node).token_and_node[1],
            } },
            .generic_type_instantiation => .{ .generic = .{
                .base = self.nodeData(node).node_and_node[0],
                .arguments = self.nodeData(node).node_and_node[1],
            } },
            .struct_type_literal => .{ .struct_literal = self.fullStructType(node).? },
            .choice_type_literal => .{ .choice_literal = .{ .variants = self.extraNodeSlice(self.nodeData(node).extra_range) } },
            else => null,
        };
    }

    pub fn fullMatch(self: *const SyntaxFile, node: NodeIndex) ?FullMatch {
        if (self.nodeTag(node) != .match_statement) return null;
        const data = self.nodeData(node).node_and_extra;
        return .{ .value = data[0], .cases = self.extraNodeSlice(self.extraData(SubRange, data[1])) };
    }

    pub fn fullBinary(self: *const SyntaxFile, node: NodeIndex) ?FullBinary {
        return switch (self.nodeTag(node)) {
            .pipe_expression,
            .unwrap_or,
            .unwrap_or_do,
            .binary_add,
            .binary_subtract,
            .binary_multiply,
            .binary_divide,
            .binary_modulo,
            .compare_equal,
            .compare_not_equal,
            .compare_less,
            .compare_greater,
            .compare_less_equal,
            .compare_greater_equal,
            .logical_and,
            .logical_or,
            .error_context,
            .index_access,
            .index_assignment,
            .pointer_assignment,
            => blk: {
                const data = self.nodeData(node).node_and_node;
                break :blk .{ .lhs = data[0], .rhs = data[1] };
            },
            else => null,
        };
    }

    pub fn fullUnary(self: *const SyntaxFile, node: NodeIndex) ?NodeIndex {
        return switch (self.nodeTag(node)) {
            .expression_statement,
            .move_expression,
            .error_propagation,
            .nullable_test,
            .defer_statement,
            .address_of,
            .address_of_mut,
            .dereference,
            => self.nodeData(node).node,
            else => null,
        };
    }

    pub fn fullNodeList(self: *const SyntaxFile, node: NodeIndex) ?[]const NodeIndex {
        return switch (self.nodeTag(node)) {
            .code_block, .list_literal, .struct_type_literal, .choice_type_literal, .reach_directive, .reach_alternative => self.extraNodeSlice(self.nodeData(node).extra_range),
            else => null,
        };
    }

    pub fn fullValueField(self: *const SyntaxFile, node: NodeIndex) ?FullValueField {
        return switch (self.nodeTag(node)) {
            .struct_value_field => .{ .name_token = self.nodeMainToken(node), .value = self.nodeData(node).node, .position = null },
            .positional_value_field => .{
                .name_token = null,
                .value = self.nodeData(node).token_and_node[1],
                .position = self.nodeData(node).token_and_node[0],
            },
            else => null,
        };
    }
};

fn decodeExtraField(comptime T: type, raw: u32) T {
    return switch (T) {
        NodeIndex, OptionalNodeIndex, ExtraIndex => @enumFromInt(raw),
        u32 => raw,
        else => if (@typeInfo(T) == .@"enum") @enumFromInt(raw) else @compileError("unsupported extra_data field " ++ @typeName(T)),
    };
}

fn optionalToken(raw: u32) ?TokenIndex {
    return if (raw == std.math.maxInt(u32)) null else raw;
}

fn tokenLexeme(content: tok.Content) []const u8 {
    return switch (content) {
        .eof => "",
        .new_line => "\n",
        .open_parenthesis => "(",
        .close_parenthesis => ")",
        .open_bracket => "[",
        .close_bracket => "]",
        .open_brace => "{",
        .close_brace => "}",
        .hash => "#",
        .dot => ".",
        .double_dot => "..",
        .comma => ",",
        .keyword_return => "return",
        .keyword_if => "if",
        .keyword_else => "else",
        .keyword_match => "match",
        .keyword_for => "for",
        .keyword_in => "in",
        .keyword_while => "while",
        .keyword_break => "break",
        .keyword_continue => "continue",
        .keyword_once => "once",
        .keyword_test => "test",
        .keyword_and => "and",
        .keyword_or => "or",
        .colon => ":",
        .double_colon => "::",
        .equal => "=",
        .arrow => "->",
        .pipe => "|",
        .tilde => "~",
        .bang => "!",
        .double_bang => "!!",
        .question_mark => "?",
        .ampersand => "&",
        .dollar => "$",
        .binary_operator => |op| switch (op) {
            .addition => "+",
            .subtraction => "-",
            .multiplication => "*",
            .division => "/",
            .modulo => "%",
        },
        .comparison_operator => |op| switch (op) {
            .equal => "==",
            .not_equal => "!=",
            .less_than => "<",
            .greater_than => ">",
            .less_than_or_equal => "<=",
            .greater_than_or_equal => ">=",
        },
        .identifier, .comment, .literal => unreachable,
    };
}

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
        unwrap_or,
        unwrap_or_do,
        pipe_expression,
        code_block,
        literal,
        list_literal,
        struct_type_literal,
        struct_type_field,
        inferred_result_field,
        choice_type_literal,
        choice_type_variant,
        choice_type_variant_default,
        struct_value_literal,
        struct_value_field,
        positional_value_field,
        choice_literal,
        choice_some_literal,
        struct_field_access,
        choice_payload_access,
        error_propagation,
        error_context,
        nullable_test,
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
        for_value,
        for_borrow,
        for_mut_borrow,
        while_statement,
        match_statement,
        match_case_value,
        match_case_borrow,
        match_case_mut_borrow,
        match_case_move,
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
        nullable_type,
        inferred_errable_type,
        generic_type_instantiation,
        array_type,
    };

    pub const Data = union {
        unused: [2]u32,
        node: NodeIndex,
        optional_node: OptionalNodeIndex,
        token: TokenIndex,
        extra: ExtraIndex,
        node_and_node: struct { NodeIndex, NodeIndex },
        node_and_optional: struct { NodeIndex, OptionalNodeIndex },
        node_and_extra: struct { NodeIndex, ExtraIndex },
        extra_and_node: struct { ExtraIndex, NodeIndex },
        u32_and_extra: struct { u32, ExtraIndex },
        token_and_node: struct { TokenIndex, NodeIndex },
        token_and_optional: struct { TokenIndex, OptionalNodeIndex },
        token_and_token: struct { TokenIndex, TokenIndex },
        extra_range: SubRange,
    };
};

pub const SubRange = struct { start: ExtraIndex, end: ExtraIndex };
pub const FunctionExtra = struct {
    generic_params_start: ExtraIndex,
    generic_params_end: ExtraIndex,
    generic_params_struct: OptionalNodeIndex,
    input: NodeIndex,
    output: NodeIndex,
    body: OptionalNodeIndex,
    pub fn genericParams(self: FunctionExtra) SubRange {
        return .{ .start = self.generic_params_start, .end = self.generic_params_end };
    }
};
pub const IfExtra = struct { then_block: NodeIndex, else_block: OptionalNodeIndex };
pub const FieldExtra = struct { type_node: OptionalNodeIndex, default_value: OptionalNodeIndex };
pub const GenericValueExtra = struct {
    generic_params_start: ExtraIndex,
    generic_params_end: ExtraIndex,
    generic_params_struct: OptionalNodeIndex,
    value: NodeIndex,
};
pub const AbstractExtra = struct {
    generic_params_start: ExtraIndex,
    generic_params_end: ExtraIndex,
    generic_params_struct: OptionalNodeIndex,
    requires_abstracts_start: ExtraIndex,
    requires_abstracts_end: ExtraIndex,
    requires_functions_start: ExtraIndex,
    requires_functions_end: ExtraIndex,
};
pub const ForExtra = struct { name_token: TokenIndex, iterable: NodeIndex, body: NodeIndex };
pub const MatchCaseExtra = struct { payload_name_token: u32, body: NodeIndex };
pub const CallExtra = struct {
    module_qualifier_token: u32,
    type_arguments_start: ExtraIndex,
    type_arguments_end: ExtraIndex,
    type_arguments_struct: OptionalNodeIndex,
    input: NodeIndex,
    pub fn typeArguments(self: CallExtra) SubRange {
        return .{ .start = self.type_arguments_start, .end = self.type_arguments_end };
    }
};

pub const FullFunction = struct {
    name_token: TokenIndex,
    generic_params: []const NodeIndex,
    generic_params_struct: ?NodeIndex,
    input: NodeIndex,
    output: NodeIndex,
    body: ?NodeIndex,
    is_once: bool,
    is_test: bool,
};
pub const FullIf = struct { condition: NodeIndex, then_block: NodeIndex, else_block: ?NodeIndex };
pub const FullCall = struct {
    callee_token: TokenIndex,
    module_qualifier_token: u32,
    type_arguments: []const NodeIndex,
    type_arguments_struct: ?NodeIndex,
    input: NodeIndex,

    pub fn moduleQualifierToken(self: FullCall) ?TokenIndex {
        return optionalToken(self.module_qualifier_token);
    }
};
pub const FullStructType = struct { fields: []const NodeIndex };
pub const FullField = struct { name_token: TokenIndex, type_node: ?NodeIndex, default_value: ?NodeIndex, is_inferred_result: bool };
pub const FullSymbol = struct { name_token: TokenIndex, type_node: ?NodeIndex, value: ?NodeIndex, mutability: Mutability };
pub const FullGenericValue = struct { name_token: TokenIndex, generic_params: []const NodeIndex, generic_params_struct: ?NodeIndex, value: NodeIndex };
pub const FullAbstract = struct {
    name_token: TokenIndex,
    generic_params: []const NodeIndex,
    generic_params_struct: ?NodeIndex,
    requires_abstracts: []const NodeIndex,
    requires_functions: []const NodeIndex,
};
pub const FullType = union(enum) {
    name: struct { name_token: TokenIndex, qualifier_token: ?TokenIndex },
    pointer: struct { child: NodeIndex, mutability: PointerMutability },
    nullable: NodeIndex,
    inferred_errable: NodeIndex,
    array: struct { length_token: TokenIndex, element: NodeIndex },
    generic: FullGenericType,
    struct_literal: FullStructType,
    choice_literal: struct { variants: []const NodeIndex },
};
pub const FullGenericType = struct { base: NodeIndex, arguments: NodeIndex };
pub const FullMatch = struct { value: NodeIndex, cases: []const NodeIndex };
pub const FullBinary = struct { lhs: NodeIndex, rhs: NodeIndex };
pub const FullValueField = struct { name_token: ?TokenIndex, value: NodeIndex, position: ?u32 };

comptime {
    std.debug.assert(@sizeOf(Node.Tag) == 1);
    if (!std.debug.runtime_safety) std.debug.assert(@sizeOf(Node.Data) == 8);
    if (!std.debug.runtime_safety) std.debug.assert(@sizeOf(Node) == 16);
    std.debug.assert(@sizeOf(NodeIndex) == 4);
    std.debug.assert(@sizeOf(OptionalNodeIndex) == 4);
}

test "compact syntax representation sizes stay fixed" {
    if (!std.debug.runtime_safety) try std.testing.expectEqual(@as(usize, 16), @sizeOf(Node));
    try std.testing.expectEqual(@as(u32, std.math.maxInt(u32)), @intFromEnum(OptionalNodeIndex.none));
}
