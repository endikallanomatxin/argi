const std = @import("std");
const source_db = @import("../1_base/source_db.zig");
const token = @import("../2_tokens/token.zig");

pub const TokenIndex = enum(u32) { _ };
pub const ExtraIndex = enum(u32) { _ };

pub const OptionalTokenIndex = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn init(index: ?TokenIndex) OptionalTokenIndex {
        return if (index) |value| @enumFromInt(@intFromEnum(value)) else .none;
    }

    pub fn unwrap(index: OptionalTokenIndex) ?TokenIndex {
        return if (index == .none) null else @enumFromInt(@intFromEnum(index));
    }
};

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

pub fn fileForRef(files: []const SyntaxFile, reference: SyntaxRef) *const SyntaxFile {
    const index: usize = @intFromEnum(reference.file_id);
    std.debug.assert(index < files.len);
    std.debug.assert(files[index].file_id == reference.file_id);
    return &files[index];
}

pub const NodeRange = extern struct {
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
        array_type,
        generic_type_instantiation,
    };

    pub const Data = extern union {
        unused: [2]u32,
        node: NodeIndex,
        optional_node: OptionalNodeIndex,
        token: TokenIndex,
        extra: ExtraIndex,
        node_and_node: extern struct { first: NodeIndex, second: NodeIndex },
        node_and_optional: extern struct { node: NodeIndex, optional: OptionalNodeIndex },
        node_and_extra: extern struct { node: NodeIndex, extra: ExtraIndex },
        extra_and_node: extern struct { extra: ExtraIndex, node: NodeIndex },
        u32_and_extra: extern struct { value: u32, extra: ExtraIndex },
        u32_and_node: extern struct { value: u32, node: NodeIndex },
        token_and_node: extern struct { token: TokenIndex, node: NodeIndex },
        token_and_token: extern struct { first: TokenIndex, second: TokenIndex },
        token_and_optional_token: extern struct { token: TokenIndex, optional: OptionalTokenIndex },
        token_and_optional: extern struct { token: TokenIndex, optional: OptionalNodeIndex },
        optional_token_and_optional_node: extern struct { token: OptionalTokenIndex, node: OptionalNodeIndex },
        extra_range: NodeRange,
    };
};

pub const Mutability = enum(u32) { constant, variable };
pub const PointerMutability = enum(u32) { read_only, read_write };

pub const FunctionExtra = struct {
    name_token: TokenIndex,
    generic_params_start: ExtraIndex,
    generic_params_end: ExtraIndex,
    generic_params_struct: OptionalNodeIndex,
    input: NodeIndex,
    output: NodeIndex,
    body: OptionalNodeIndex,
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
pub const CallExtra = struct {
    module_qualifier: OptionalTokenIndex,
    type_arguments_start: ExtraIndex,
    type_arguments_end: ExtraIndex,
    type_arguments_struct: OptionalNodeIndex,
    input: NodeIndex,
};
pub const ForExtra = struct { name_token: TokenIndex, iterable: NodeIndex, body: NodeIndex };
pub const MatchCaseExtra = struct { payload_name: OptionalTokenIndex, body: NodeIndex };

pub const FunctionDeclaration = struct {
    name_token: TokenIndex,
    generic_params: []const NodeIndex,
    generic_params_struct: ?NodeIndex,
    input: NodeIndex,
    output: NodeIndex,
    body: ?NodeIndex,
    is_once: bool,
};
pub const TestDeclaration = struct { function: FunctionDeclaration };
pub const FunctionName = union(enum) {
    identifier: TokenIndex,
    operator: OperatorName,
};
pub const OperatorName = enum {
    add,
    equal,
    not_equal,
    get,
    set,
    get_ro_pointer,
    get_rw_pointer,
};
pub const IfStatement = struct { condition: NodeIndex, then_block: NodeIndex, else_block: ?NodeIndex };
pub const FunctionCall = struct {
    callee_token: TokenIndex,
    module_qualifier: ?TokenIndex,
    type_arguments: []const NodeIndex,
    type_arguments_struct: ?NodeIndex,
    input: NodeIndex,
};
pub const StructTypeLiteral = struct { fields: []const NodeIndex };
pub const ChoiceTypeLiteral = struct { variants: []const NodeIndex };
pub const StructValueLiteral = struct { fields: []const NodeIndex, positional_prefix_count: u32 };
pub const CodeBlock = struct { statements: []const NodeIndex };
pub const ListLiteral = struct { elements: []const NodeIndex };
pub const StructTypeField = struct { name_token: TokenIndex, type_node: ?NodeIndex, default_value: ?NodeIndex, inferred_result: bool };
pub const SymbolDeclaration = struct { name_token: TokenIndex, type_node: ?NodeIndex, value: ?NodeIndex, mutability: Mutability };
pub const TypeDeclaration = struct { name_token: TokenIndex, generic_params: []const NodeIndex, generic_params_struct: ?NodeIndex, value: NodeIndex };
pub const CEnumDeclaration = struct { name_token: TokenIndex, generic_params: []const NodeIndex, generic_params_struct: ?NodeIndex, value: NodeIndex };
pub const CUnionDeclaration = struct { name_token: TokenIndex, generic_params: []const NodeIndex, generic_params_struct: ?NodeIndex, value: NodeIndex };
pub const AbstractImplements = struct { concrete_name_token: TokenIndex, generic_params: []const NodeIndex, generic_params_struct: ?NodeIndex, abstract_type: NodeIndex };
pub const AbstractDefaultsTo = struct { name_token: TokenIndex, generic_params: []const NodeIndex, generic_params_struct: ?NodeIndex, type_node: NodeIndex };
pub const AbstractDeclaration = struct {
    name_token: TokenIndex,
    generic_params: []const NodeIndex,
    generic_params_struct: ?NodeIndex,
    requires_abstracts: []const NodeIndex,
    requires_functions: []const NodeIndex,
};
pub const GenericType = struct { base: NodeIndex, arguments: NodeIndex };
pub const Type = union(enum) {
    name: struct { name_token: TokenIndex, qualifier_token: ?TokenIndex },
    pointer: struct { child: NodeIndex, mutability: PointerMutability },
    nullable: NodeIndex,
    inferred_errable: NodeIndex,
    array: struct { length_token: TokenIndex, element: NodeIndex },
    generic: GenericType,
    struct_literal: StructTypeLiteral,
    choice_literal: ChoiceTypeLiteral,
};
pub const MatchStatement = struct { value: NodeIndex, cases: []const NodeIndex };
pub const BinaryOperation = struct { lhs: NodeIndex, rhs: NodeIndex };

pub const TokenList = std.MultiArrayList(token.Token);
pub const NodeList = std.MultiArrayList(Node);

pub const SyntaxFile = struct {
    file_id: source_db.FileId,
    tokens: TokenList = .empty,
    nodes: NodeList = .empty,
    extra_data: std.ArrayList(u32) = .empty,
    roots: []NodeIndex = &.{},

    pub const StorageMetrics = struct {
        token_bytes: usize,
        node_base_bytes: usize,
        extra_data_bytes: usize,
        root_bytes: usize,

        pub fn total(metrics: StorageMetrics) usize {
            return metrics.token_bytes + metrics.node_base_bytes + metrics.extra_data_bytes + metrics.root_bytes;
        }
    };

    // Representative syntaxing measurements compare the compact base and
    // extra_data with the legacy tree's 128-byte logical STNode records:
    // minimal: 10 nodes, 130 + 44 bytes (legacy 6 nodes, 768 bytes);
    // cat_cli: 143 nodes, 1,859 + 640 bytes (legacy 120, 15,360 bytes);
    // dynamic array: 222 nodes, 2,886 + 696 bytes (legacy 184, 23,552 bytes).
    // Compact counts include type syntax, which the legacy parallel Type tree
    // omitted from its STNode count.

    pub fn init(allocator: std.mem.Allocator, file_id: source_db.FileId, tokens: []const token.Token) !SyntaxFile {
        var tree: SyntaxFile = .{ .file_id = file_id };
        errdefer tree.deinit(allocator);
        try tree.tokens.ensureTotalCapacity(allocator, tokens.len);
        for (tokens) |item| tree.tokens.appendAssumeCapacity(item);
        return tree;
    }

    pub fn deinit(tree: *SyntaxFile, allocator: std.mem.Allocator) void {
        tree.tokens.deinit(allocator);
        tree.nodes.deinit(allocator);
        tree.extra_data.deinit(allocator);
        allocator.free(tree.roots);
        tree.* = undefined;
    }

    pub fn storageMetrics(tree: *const SyntaxFile) StorageMetrics {
        return .{
            .token_bytes = tree.tokens.len * (@sizeOf(token.Content) + @sizeOf(token.Location)),
            .node_base_bytes = tree.nodes.len * (@sizeOf(Node.Tag) + @sizeOf(TokenIndex) + @sizeOf(Node.Data)),
            .extra_data_bytes = tree.extra_data.items.len * @sizeOf(u32),
            .root_bytes = tree.roots.len * @sizeOf(NodeIndex),
        };
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

    pub fn addNodeRange(tree: *SyntaxFile, allocator: std.mem.Allocator, values: []const NodeIndex) !NodeRange {
        if (tree.extra_data.items.len + values.len > std.math.maxInt(u32)) return error.SyntaxTreeTooLarge;
        try tree.extra_data.ensureUnusedCapacity(allocator, values.len);
        const start: ExtraIndex = @enumFromInt(@as(u32, @intCast(tree.extra_data.items.len)));
        for (values) |value| tree.extra_data.appendAssumeCapacity(@intFromEnum(value));
        return .{
            .start = start,
            .end = @enumFromInt(@as(u32, @intCast(tree.extra_data.items.len))),
        };
    }

    pub fn nodeRange(tree: *const SyntaxFile, range: NodeRange) []const NodeIndex {
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
                .char_literal => sourceCharLiteral(source, tree.tokens.items(.location)[token_index].offset),
            },
            else => fixedTokenText(contents),
        };
    }

    pub fn functionDeclaration(tree: *const SyntaxFile, node: NodeIndex) ?FunctionDeclaration {
        const node_tag = tree.tag(node);
        if (node_tag != .function_declaration and node_tag != .function_declaration_once) return null;
        const extra = tree.extraData(FunctionExtra, tree.data(node).extra);
        return .{
            .name_token = extra.name_token,
            .generic_params = tree.nodeRange(.{ .start = extra.generic_params_start, .end = extra.generic_params_end }),
            .generic_params_struct = extra.generic_params_struct.unwrap(),
            .input = extra.input,
            .output = extra.output,
            .body = extra.body.unwrap(),
            .is_once = node_tag == .function_declaration_once,
        };
    }

    pub fn testDeclaration(tree: *const SyntaxFile, node: NodeIndex) ?TestDeclaration {
        if (tree.tag(node) != .test_declaration) return null;
        const extra = tree.extraData(FunctionExtra, tree.data(node).extra);
        return .{ .function = .{
            .name_token = extra.name_token,
            .generic_params = tree.nodeRange(.{ .start = extra.generic_params_start, .end = extra.generic_params_end }),
            .generic_params_struct = extra.generic_params_struct.unwrap(),
            .input = extra.input,
            .output = extra.output,
            .body = extra.body.unwrap(),
            .is_once = false,
        } };
    }

    pub fn functionName(tree: *const SyntaxFile, db: *const source_db.SourceDb, node: NodeIndex) ?FunctionName {
        const declaration = tree.functionDeclaration(node) orelse (tree.testDeclaration(node) orelse return null).function;
        if (!std.mem.eql(u8, tree.tokenText(db, declaration.name_token), "operator")) {
            return .{ .identifier = declaration.name_token };
        }

        const operator_index = @intFromEnum(declaration.name_token) + 1;
        if (operator_index >= tree.tokens.len) return null;
        return switch (tree.tokens.items(.content)[operator_index]) {
            .binary_operator => |operator| if (operator == .addition) .{ .operator = .add } else null,
            .comparison_operator => |operator| switch (operator) {
                .equal => .{ .operator = .equal },
                .not_equal => .{ .operator = .not_equal },
                else => null,
            },
            .identifier => |range| blk: {
                const text = range.slice(db.get(tree.file_id).source);
                if (std.mem.eql(u8, text, "get")) break :blk .{ .operator = .get };
                if (std.mem.eql(u8, text, "set")) break :blk .{ .operator = .set };
                if (std.mem.eql(u8, text, "get_ro_pointer")) break :blk .{ .operator = .get_ro_pointer };
                if (std.mem.eql(u8, text, "get_rw_pointer")) break :blk .{ .operator = .get_rw_pointer };
                break :blk null;
            },
            else => null,
        };
    }

    pub fn ifStatement(tree: *const SyntaxFile, node: NodeIndex) ?IfStatement {
        if (tree.tag(node) != .if_statement) return null;
        const node_data = tree.data(node).node_and_extra;
        const extra = tree.extraData(IfExtra, node_data.extra);
        return .{ .condition = node_data.node, .then_block = extra.then_block, .else_block = extra.else_block.unwrap() };
    }

    pub fn functionCall(tree: *const SyntaxFile, node: NodeIndex) ?FunctionCall {
        if (tree.tag(node) != .function_call) return null;
        const extra = tree.extraData(CallExtra, tree.data(node).extra);
        return .{
            .callee_token = tree.mainToken(node),
            .module_qualifier = extra.module_qualifier.unwrap(),
            .type_arguments = tree.nodeRange(.{ .start = extra.type_arguments_start, .end = extra.type_arguments_end }),
            .type_arguments_struct = extra.type_arguments_struct.unwrap(),
            .input = extra.input,
        };
    }

    pub fn structTypeLiteral(tree: *const SyntaxFile, node: NodeIndex) ?StructTypeLiteral {
        if (tree.tag(node) != .struct_type_literal) return null;
        return .{ .fields = tree.nodeRange(tree.data(node).extra_range) };
    }

    pub fn choiceTypeLiteral(tree: *const SyntaxFile, node: NodeIndex) ?ChoiceTypeLiteral {
        if (tree.tag(node) != .choice_type_literal) return null;
        return .{ .variants = tree.nodeRange(tree.data(node).extra_range) };
    }

    pub fn structValueLiteral(tree: *const SyntaxFile, node: NodeIndex) ?StructValueLiteral {
        if (tree.tag(node) != .struct_value_literal) return null;
        const node_data = tree.data(node).u32_and_extra;
        return .{
            .fields = tree.nodeRange(tree.extraData(NodeRange, node_data.extra)),
            .positional_prefix_count = node_data.value,
        };
    }

    pub fn codeBlock(tree: *const SyntaxFile, node: NodeIndex) ?CodeBlock {
        if (tree.tag(node) != .code_block) return null;
        return .{ .statements = tree.nodeRange(tree.data(node).extra_range) };
    }

    pub fn listLiteral(tree: *const SyntaxFile, node: NodeIndex) ?ListLiteral {
        if (tree.tag(node) != .list_literal) return null;
        return .{ .elements = tree.nodeRange(tree.data(node).extra_range) };
    }

    pub fn structTypeField(tree: *const SyntaxFile, node: NodeIndex) ?StructTypeField {
        const node_tag = tree.tag(node);
        if (node_tag != .struct_type_field and node_tag != .inferred_result_field) return null;
        const extra = tree.extraData(FieldExtra, tree.data(node).extra);
        return .{
            .name_token = tree.mainToken(node),
            .type_node = extra.type_node.unwrap(),
            .default_value = extra.default_value.unwrap(),
            .inferred_result = node_tag == .inferred_result_field,
        };
    }

    pub fn symbolDeclaration(tree: *const SyntaxFile, node: NodeIndex) ?SymbolDeclaration {
        const node_tag = tree.tag(node);
        if (node_tag != .symbol_declaration_constant and node_tag != .symbol_declaration_variable) return null;
        const extra = tree.extraData(FieldExtra, tree.data(node).extra);
        return .{
            .name_token = tree.mainToken(node),
            .type_node = extra.type_node.unwrap(),
            .value = extra.default_value.unwrap(),
            .mutability = if (node_tag == .symbol_declaration_variable) .variable else .constant,
        };
    }

    const GenericValuePayload = struct {
        name_token: TokenIndex,
        generic_params: []const NodeIndex,
        generic_params_struct: ?NodeIndex,
        value: NodeIndex,
    };

    fn genericValuePayload(tree: *const SyntaxFile, node: NodeIndex) GenericValuePayload {
        const extra = tree.extraData(GenericValueExtra, tree.data(node).extra);
        return .{
            .name_token = tree.mainToken(node),
            .generic_params = tree.nodeRange(.{ .start = extra.generic_params_start, .end = extra.generic_params_end }),
            .generic_params_struct = extra.generic_params_struct.unwrap(),
            .value = extra.value,
        };
    }

    pub fn typeDeclaration(tree: *const SyntaxFile, node: NodeIndex) ?TypeDeclaration {
        if (tree.tag(node) != .type_declaration) return null;
        const payload = tree.genericValuePayload(node);
        return .{ .name_token = payload.name_token, .generic_params = payload.generic_params, .generic_params_struct = payload.generic_params_struct, .value = payload.value };
    }

    pub fn cEnumDeclaration(tree: *const SyntaxFile, node: NodeIndex) ?CEnumDeclaration {
        if (tree.tag(node) != .c_enum_declaration) return null;
        const payload = tree.genericValuePayload(node);
        return .{ .name_token = payload.name_token, .generic_params = payload.generic_params, .generic_params_struct = payload.generic_params_struct, .value = payload.value };
    }

    pub fn cUnionDeclaration(tree: *const SyntaxFile, node: NodeIndex) ?CUnionDeclaration {
        if (tree.tag(node) != .c_union_declaration) return null;
        const payload = tree.genericValuePayload(node);
        return .{ .name_token = payload.name_token, .generic_params = payload.generic_params, .generic_params_struct = payload.generic_params_struct, .value = payload.value };
    }

    pub fn abstractImplements(tree: *const SyntaxFile, node: NodeIndex) ?AbstractImplements {
        if (tree.tag(node) != .abstract_implements) return null;
        const payload = tree.genericValuePayload(node);
        return .{ .concrete_name_token = payload.name_token, .generic_params = payload.generic_params, .generic_params_struct = payload.generic_params_struct, .abstract_type = payload.value };
    }

    pub fn abstractDefaultsTo(tree: *const SyntaxFile, node: NodeIndex) ?AbstractDefaultsTo {
        if (tree.tag(node) != .abstract_defaultsto) return null;
        const payload = tree.genericValuePayload(node);
        return .{ .name_token = payload.name_token, .generic_params = payload.generic_params, .generic_params_struct = payload.generic_params_struct, .type_node = payload.value };
    }

    pub fn abstractDeclaration(tree: *const SyntaxFile, node: NodeIndex) ?AbstractDeclaration {
        if (tree.tag(node) != .abstract_declaration) return null;
        const extra = tree.extraData(AbstractExtra, tree.data(node).extra);
        return .{
            .name_token = tree.mainToken(node),
            .generic_params = tree.nodeRange(.{ .start = extra.generic_params_start, .end = extra.generic_params_end }),
            .generic_params_struct = extra.generic_params_struct.unwrap(),
            .requires_abstracts = tree.nodeRange(.{ .start = extra.requires_abstracts_start, .end = extra.requires_abstracts_end }),
            .requires_functions = tree.nodeRange(.{ .start = extra.requires_functions_start, .end = extra.requires_functions_end }),
        };
    }

    pub fn syntaxType(tree: *const SyntaxFile, node: NodeIndex) ?Type {
        return switch (tree.tag(node)) {
            .type_name => .{ .name = .{
                .name_token = tree.mainToken(node),
                .qualifier_token = tree.data(node).token_and_optional_token.optional.unwrap(),
            } },
            .pointer_type => .{ .pointer = .{ .child = tree.data(node).node, .mutability = .read_only } },
            .pointer_type_mut => .{ .pointer = .{ .child = tree.data(node).node, .mutability = .read_write } },
            .nullable_type => .{ .nullable = tree.data(node).node },
            .inferred_errable_type => .{ .inferred_errable = tree.data(node).node },
            .array_type => .{ .array = .{ .length_token = tree.data(node).token_and_node.token, .element = tree.data(node).token_and_node.node } },
            .generic_type_instantiation => .{ .generic = .{ .base = tree.data(node).node_and_node.first, .arguments = tree.data(node).node_and_node.second } },
            .struct_type_literal => .{ .struct_literal = tree.structTypeLiteral(node).? },
            .choice_type_literal => .{ .choice_literal = tree.choiceTypeLiteral(node).? },
            else => null,
        };
    }

    pub fn matchStatement(tree: *const SyntaxFile, node: NodeIndex) ?MatchStatement {
        if (tree.tag(node) != .match_statement) return null;
        const node_data = tree.data(node).node_and_extra;
        return .{ .value = node_data.node, .cases = tree.nodeRange(tree.extraData(NodeRange, node_data.extra)) };
    }

    pub fn binaryOperation(tree: *const SyntaxFile, node: NodeIndex) ?BinaryOperation {
        return switch (tree.tag(node)) {
            .pipe_expression, .unwrap_or, .unwrap_or_do, .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo, .compare_equal, .compare_not_equal, .compare_less, .compare_greater, .compare_less_equal, .compare_greater_equal, .logical_and, .logical_or, .error_context, .index_access, .index_assignment, .pointer_assignment => .{
                .lhs = tree.data(node).node_and_node.first,
                .rhs = tree.data(node).node_and_node.second,
            },
            else => null,
        };
    }

    pub fn unaryOperand(tree: *const SyntaxFile, node: NodeIndex) ?NodeIndex {
        return switch (tree.tag(node)) {
            .expression_statement, .move_expression, .error_propagation, .nullable_test, .defer_statement, .address_of, .address_of_mut, .dereference => tree.data(node).node,
            else => null,
        };
    }
};

fn sourceCharLiteral(source: []const u8, start: u32) []const u8 {
    var index: usize = start + 1;
    var escaped = false;
    while (index < source.len) : (index += 1) {
        const byte = source[index];
        if (!escaped and byte == '\'') return source[start .. index + 1];
        if (!escaped and byte == '\\') {
            escaped = true;
        } else {
            escaped = false;
        }
    }
    return source[start..];
}

fn fixedTokenText(content: token.Content) []const u8 {
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
        .binary_operator => |operator| switch (operator) {
            .addition => "+",
            .subtraction => "-",
            .multiplication => "*",
            .division => "/",
            .modulo => "%",
        },
        .comparison_operator => |operator| switch (operator) {
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
