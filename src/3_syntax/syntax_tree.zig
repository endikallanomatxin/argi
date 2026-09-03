const std = @import("std");
const source_db = @import("../1_base/source_db.zig");
const tok = @import("../2_tokens/token.zig");
const syn = @import("syntax_tree.zig");

// Types used from token.zig

pub const ST = struct {
    nodes: []const *STNode,
};

pub const STNode = struct {
    location: tok.Location,
    content: Content,
};

/// Stable index into one file's syntax artifact. Index zero is a valid node;
/// stores are always addressed together with their owning FileId.
pub const NodeId = u32;

pub const OptionalNodeId = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn fromOptional(id: ?NodeId) OptionalNodeId {
        return if (id) |value| @enumFromInt(value) else .none;
    }

    pub fn unwrap(self: OptionalNodeId) ?NodeId {
        return if (self == .none) null else @intFromEnum(self);
    }
};

pub const ExtraIndex = u32;

/// Half-open range in `SyntaxStore.extra_data`. Entries in a node range are
/// NodeIds encoded as u32, so the backing bytes can be persisted verbatim.
pub const NodeRange = struct {
    start: ExtraIndex = 0,
    end: ExtraIndex = 0,
};

/// Module-level reference to a node. Child references need only `NodeId`
/// because syntax trees never cross file boundaries.
pub const SyntaxRef = struct {
    file_id: source_db.FileId,
    node_id: NodeId,
};

/// Dense ownership for syntax nodes. Fixed-size pages keep the legacy adapter's
/// pointers stable without reserving memory proportional to all tokens. NodeId
/// remains a linear index, so serialization can flatten pages without changing
/// any reference.
pub const SyntaxStore = struct {
    pub const page_capacity = 256;

    allocator: std.mem.Allocator,
    pages: std.array_list.Managed([]STNode),
    node_count: usize = 0,
    extra_data: std.array_list.Managed(u32),
    roots: NodeRange = .{},

    pub const Storage = struct {
        logical_bytes: usize,
        allocated_bytes: usize,
        node_capacity: usize,
    };

    pub fn init(allocator: std.mem.Allocator) SyntaxStore {
        return .{
            .allocator = allocator,
            .pages = std.array_list.Managed([]STNode).init(allocator),
            .extra_data = std.array_list.Managed(u32).init(allocator),
        };
    }

    pub fn deinit(self: *SyntaxStore) void {
        for (self.pages.items) |page| self.allocator.free(page);
        self.pages.deinit();
        self.extra_data.deinit();
    }

    pub fn count(self: *const SyntaxStore) usize {
        return self.node_count;
    }

    pub fn append(self: *SyntaxStore, node: STNode) !struct { id: NodeId, ptr: *STNode } {
        const index = self.node_count;
        std.debug.assert(index <= std.math.maxInt(NodeId));
        const page_index = index / page_capacity;
        const item_index = index % page_capacity;
        if (page_index == self.pages.items.len) {
            const page = try self.allocator.alloc(STNode, page_capacity);
            errdefer self.allocator.free(page);
            try self.pages.append(page);
        }
        self.pages.items[page_index][item_index] = node;
        self.node_count += 1;
        return .{ .id = @intCast(index), .ptr = &self.pages.items[page_index][item_index] };
    }

    pub fn get(self: *const SyntaxStore, id: NodeId) *const STNode {
        const index: usize = id;
        std.debug.assert(index < self.node_count);
        return &self.pages.items[index / page_capacity][index % page_capacity];
    }

    pub fn getMut(self: *SyntaxStore, id: NodeId) *STNode {
        const index: usize = id;
        std.debug.assert(index < self.node_count);
        return &self.pages.items[index / page_capacity][index % page_capacity];
    }

    pub fn idFromPtr(self: *const SyntaxStore, node: *const STNode) NodeId {
        const current = @intFromPtr(node);
        for (self.pages.items, 0..) |page, page_index| {
            const first = @intFromPtr(page.ptr);
            const end = first + page.len * @sizeOf(STNode);
            if (current < first or current >= end) continue;
            const offset = current - first;
            std.debug.assert(offset % @sizeOf(STNode) == 0);
            const index = page_index * page_capacity + offset / @sizeOf(STNode);
            std.debug.assert(index < self.node_count);
            return @intCast(index);
        }
        unreachable;
    }

    pub fn appendNodeList(self: *SyntaxStore, ids: []const NodeId) !NodeRange {
        std.debug.assert(self.extra_data.items.len <= std.math.maxInt(ExtraIndex));
        const start: ExtraIndex = @intCast(self.extra_data.items.len);
        try self.extra_data.appendSlice(ids);
        std.debug.assert(self.extra_data.items.len <= std.math.maxInt(ExtraIndex));
        return .{ .start = start, .end = @intCast(self.extra_data.items.len) };
    }

    pub fn nodeList(self: *const SyntaxStore, range: NodeRange) []const NodeId {
        return @ptrCast(self.extra_data.items[range.start..range.end]);
    }

    pub fn setRoots(self: *SyntaxStore, ids: []const NodeId) !void {
        std.debug.assert(self.roots.start == self.roots.end);
        self.roots = try self.appendNodeList(ids);
    }

    pub fn rootNodes(self: *const SyntaxStore) []const NodeId {
        return self.nodeList(self.roots);
    }

    pub fn byteSize(self: *const SyntaxStore) usize {
        return self.node_count * @sizeOf(STNode) + self.extra_data.items.len * @sizeOf(u32);
    }

    /// Includes unused slots in fixed node pages and the capacities of the
    /// store's own index arrays. It intentionally excludes allocator-private
    /// bookkeeping and the temporary pointer adapter.
    pub fn storage(self: *const SyntaxStore) Storage {
        const node_capacity = self.pages.items.len * page_capacity;
        return .{
            .logical_bytes = self.byteSize(),
            .allocated_bytes = node_capacity * @sizeOf(STNode) +
                self.pages.capacity * @sizeOf([]STNode) +
                self.extra_data.capacity * @sizeOf(u32),
            .node_capacity = node_capacity,
        };
    }
};

pub const FileSyntax = struct {
    file_id: source_db.FileId,
    store: SyntaxStore,
};

pub const Name = struct {
    string: []const u8,
    location: tok.Location,
    // Location is used mainly for the lsp
};

pub const Content = union(enum) {
    choice_option_declaration: ChoiceOptionDeclaration,
    symbol_declaration: SymbolDeclaration,
    type_declaration: TypeDeclaration,

    // Abstract type features
    abstract_declaration: AbstractDeclaration,
    abstract_implements: AbstractImplements,
    abstract_defaultsto: AbstractDefault,
    function_declaration: FunctionDeclaration,
    test_declaration: TestDeclaration,
    assignment: Assignment,
    expression_statement: *STNode,
    identifier: []const u8,
    pipe_placeholder: struct {},
    reach_directive: ReachDirective,
    move_expression: *STNode,
    function_call: FunctionCall,
    pipe_expression: PipeExpression,
    code_block: CodeBlock,

    // Literals
    // (Not parsed until the type is known)
    literal: tok.Literal,
    list_literal: ListLiteral,
    struct_type_literal: StructTypeLiteral,
    choice_type_literal: ChoiceTypeLiteral,
    struct_value_literal: StructValueLiteral,
    choice_literal: ChoiceLiteral,

    struct_field_access: StructFieldAccess,
    choice_payload_access: ChoicePayloadAccess,
    error_propagation: ErrorPropagation,
    error_context: ErrorContext,
    index_access: IndexAccess,

    return_statement: ReturnStatement,
    break_statement: struct {},
    continue_statement: struct {},
    binary_operation: BinaryOperation,
    comparison: Comparison,
    logical_operation: LogicalOperation,
    if_statement: IfStatement,
    for_statement: ForStatement,
    while_statement: WhileStatement,
    match_statement: MatchStatement,
    import_statement: ImportStatement,
    defer_statement: *STNode,
    keep_statement: Name,
    index_assignment: IndexAssignment,
    address_of: AddressOf,
    dereference: *STNode,
    pointer_assignment: PointerAssignment,
};

pub const PointerMutability = enum {
    read_only,
    read_write,
};

pub const Type = union(enum) {
    type_name: Name,
    struct_type_literal: StructTypeLiteral,
    choice_type_literal: ChoiceTypeLiteral,
    pointer_type: *PointerType,
    inferred_errable: *Type,
    generic_type_instantiation: struct {
        base_name: Name,
        args: StructTypeLiteral,
    },
    array_type: *ArrayType,
};

pub const PointerType = struct {
    mutability: PointerMutability,
    child: *Type,
};

pub const ArrayType = struct {
    length: usize,
    element: *Type,
};

pub const AddressOf = struct {
    value: *STNode,
    mutability: PointerMutability,
};

pub const SymbolDeclaration = struct {
    name: Name,
    type: ?Type,
    mutability: Mutability,
    value: ?*STNode,
};

pub const TypeDeclaration = struct {
    name: Name,
    generic_params: []const []const u8,
    generic_params_struct: ?StructTypeLiteral,
    kind: Kind = .regular,
    value: *STNode,

    pub const Kind = enum {
        regular,
        c_enum,
        c_union,
    };
};

pub const ChoiceOptionDeclaration = struct {
    name: Name,
};

// Abstract type declarations (interface-like)
pub const AbstractDeclaration = struct {
    name: Name,
    generic_params: []const []const u8,
    generic_params_struct: ?StructTypeLiteral,
    // Composed abstracts (by name)
    requires_abstracts: []const []const u8,
    // Function requirements
    requires_functions: []const AbstractFunctionRequirement,
};

// "ConcreteType implements AbstractType" implementation relation
pub const AbstractImplements = struct {
    concrete_name: Name,
    generic_params: []const []const u8,
    generic_params_struct: ?StructTypeLiteral,
    abstract_ty: Type,
};

// "Name defaultsto Type" default concrete backing type
pub const AbstractDefault = struct {
    name: Name,
    generic_params: []const []const u8,
    generic_params_struct: ?StructTypeLiteral,
    ty: Type,
};

pub const AbstractFunctionRequirement = struct {
    name: Name,
    input: StructTypeLiteral,
    output: StructTypeLiteral,
};

pub const FunctionDeclaration = struct {
    name: Name,
    is_once: bool,
    generic_params: []const []const u8,
    generic_params_struct: ?StructTypeLiteral,
    input: StructTypeLiteral, // Arguments
    output: StructTypeLiteral, // Named return params
    body: ?*STNode, // CodeBlock
    // If it has no body, it is an extern function.
};

pub const TestDeclaration = struct {
    decl: FunctionDeclaration,
};

pub const Assignment = struct {
    name: Name,
    value: *STNode,
};

pub const FunctionCall = struct {
    callee: []const u8,
    callee_loc: tok.Location,
    module_qualifier: ?[]const u8,
    // Optional explicit type arguments on call site (e.g. foo[Int32, &Char])
    type_arguments: ?[]const Type,
    // Alternative syntax: named type arguments via struct-like block: #(.T: Int32)
    type_arguments_struct: ?StructTypeLiteral,
    input: *const STNode, // Arguments
};

pub const PipeExpression = struct {
    left: *STNode,
    right: *STNode,
};

pub const Mutability = enum {
    constant,
    variable,
};

pub const CodeBlock = struct {
    items: []const *STNode,
    // Return args in the future.
};

pub const ListLiteral = struct {
    element_type: ?Type, // Optional explicit type
    elements: []const *STNode,
};

pub const StructTypeLiteral = struct {
    fields: []const StructTypeLiteralField,
};

pub const StructTypeLiteralField = struct {
    name: Name,
    type: ?Type,
    default_value: ?*STNode, // Optional default value for the field
};

pub const StructValueLiteral = struct {
    fields: []const StructValueLiteralField,
    positional_prefix_count: u32 = 0,
};

pub const ChoiceTypeLiteral = struct {
    variants: []const ChoiceTypeLiteralVariant,
};

pub const ChoiceTypeLiteralVariant = struct {
    name: Name,
    module_qualifier: ?Name = null,
    is_default: bool,
    payload_type: ?Type = null,
};

pub const ChoiceLiteral = struct {
    name: Name,
    module_qualifier: ?Name = null,
    payload: ?*STNode,
};

pub const StructValueLiteralField = struct {
    name: Name,
    value: *STNode,
};

pub const StructFieldAccess = struct {
    struct_value: *STNode,
    field_name: Name,
};

pub const ReachDirective = struct {
    alternatives: []const ReachAlternative,
};

pub const ReachAlternative = struct {
    segments: []const Name,
};

pub const ChoicePayloadAccess = struct {
    choice_value: *STNode,
    variant_name: Name,
};

pub const ErrorPropagation = struct {
    value: *STNode,
};

pub const ErrorContext = struct {
    value: *STNode,
    context: *STNode,
};

pub const IndexAccess = struct {
    value: *STNode,
    index: *STNode,
};

pub const IndexAssignment = struct {
    target: *STNode,
    value: *STNode,
};

pub const BinaryOperation = struct {
    operator: tok.BinaryOperator,
    left: *STNode,
    right: *STNode,
};

pub const Comparison = struct {
    operator: tok.ComparisonOperator,
    left: *STNode,
    right: *STNode,
};

pub const LogicalOperator = enum {
    and_,
    or_,
};

pub const LogicalOperation = struct {
    operator: LogicalOperator,
    left: *STNode,
    right: *STNode,
};

pub const IfStatement = struct {
    condition: *STNode,
    then_block: *STNode,
    else_block: ?*STNode,
};

pub const WhileStatement = struct {
    condition: *STNode,
    body: *STNode,
};

pub const ForStatement = struct {
    item_mode: ForBindingMode,
    item_name: Name,
    iterable: *STNode,
    body: *STNode,
};

pub const ForBindingMode = enum {
    by_value,
    by_borrow,
    by_mut_borrow,
};

pub const MatchStatement = struct {
    value: *STNode,
    cases: []const MatchCase,
};

pub const MatchPayloadBindingMode = enum {
    by_value,
    by_borrow,
    by_mut_borrow,
    by_move,
};

pub const MatchCase = struct {
    variant_name: Name,
    payload_binding: ?MatchPayloadBinding,
    body: *STNode,
};

pub const MatchPayloadBinding = struct {
    mode: MatchPayloadBindingMode,
    name: Name,
};

pub const ReturnStatement = struct {
    expression: ?*STNode,
};

pub const ImportStatement = struct {
    path: []const u8,
};

pub const PointerAssignment = struct {
    target: *STNode, // Dereference node
    value: *STNode, // Value to assign
};
