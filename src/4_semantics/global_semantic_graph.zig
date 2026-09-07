const std = @import("std");
const primitives = @import("semantic_primitives.zig");
const semantic_strings = @import("semantic_strings.zig");

pub const GlobalDeclId = enum(u32) { _ };
pub const GlobalTypeId = enum(u32) { _ };
pub const GlobalFunctionId = enum(u32) { _ };
pub const GlobalBindingId = enum(u32) { _ };
pub const GlobalNodeId = enum(u32) { _ };
pub const GlobalBlockId = enum(u32) { _ };
pub const GlobalFieldId = enum(u32) { _ };
pub const GlobalVariantId = enum(u32) { _ };
pub const GlobalGenericArgId = enum(u32) { _ };
pub const GlobalFileId = enum(u32) { _ };
pub const GlobalModuleId = enum(u32) { _ };

pub const StringRange = primitives.StringRange;
pub const DeclRange = primitives.Range(GlobalDeclId);
pub const TypeRange = primitives.Range(GlobalTypeId);
pub const FunctionRange = primitives.Range(GlobalFunctionId);
pub const BindingRange = primitives.Range(GlobalBindingId);
pub const NodeRange = primitives.Range(GlobalNodeId);
pub const BlockRange = primitives.Range(GlobalBlockId);
pub const FieldRange = primitives.Range(GlobalFieldId);
pub const VariantRange = primitives.Range(GlobalVariantId);
pub const GenericArgRange = primitives.Range(GlobalGenericArgId);

pub const GlobalType = primitives.SemanticType(GlobalTypeId, GlobalDeclId, GlobalFieldId, GlobalGenericArgId);
pub const Field = primitives.Field(GlobalTypeId, GlobalNodeId);
pub const ChoiceVariant = primitives.ChoiceVariant(GlobalTypeId, GlobalDeclId);
pub const GenericTypeArgument = primitives.GenericTypeArgument(GlobalTypeId);
pub const Function = primitives.Function(GlobalDeclId, GlobalFieldId, GlobalBlockId, GlobalBindingId, GlobalTypeId);
pub const Binding = primitives.Binding(GlobalTypeId, GlobalNodeId);
pub const Block = primitives.Block(GlobalNodeId);
pub const Node = primitives.Node(GlobalNodeId, GlobalTypeId, GlobalDeclId, GlobalFunctionId, GlobalBindingId, GlobalBlockId, GlobalFieldId, GlobalVariantId);

pub const File = struct {
    module: GlobalModuleId,
    path: StringRange,
};

pub const Module = struct {
    dir: StringRange,
    files: primitives.Range(GlobalFileId),
    declarations: DeclRange,
};

pub const Declaration = struct {
    kind: primitives.DeclarationKind,
    name: StringRange,
    source: primitives.SourceRef,
    type_id: ?GlobalTypeId = null,
    function_id: ?GlobalFunctionId = null,
    struct_fields: ?FieldRange = null,
    choice_variants: ?VariantRange = null,
    generic_parameter_count: ?u32 = null,
};

pub const Symbol = struct {
    name: StringRange,
    declarations: DeclRange,
};

pub const GlobalSemanticGraph = struct {
    modules: std.ArrayList(Module) = .empty,
    files: std.ArrayList(File) = .empty,
    declarations: std.ArrayList(Declaration) = .empty,
    symbols: std.ArrayList(Symbol) = .empty,
    symbol_declarations: std.ArrayList(GlobalDeclId) = .empty,
    types: std.ArrayList(GlobalType) = .empty,
    functions: std.ArrayList(Function) = .empty,
    bindings: std.ArrayList(Binding) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    blocks: std.ArrayList(Block) = .empty,
    block_nodes: std.ArrayList(GlobalNodeId) = .empty,
    fields: std.ArrayList(Field) = .empty,
    variants: std.ArrayList(ChoiceVariant) = .empty,
    generic_arguments: std.ArrayList(GenericTypeArgument) = .empty,
    strings: std.ArrayList(u8) = .empty,
    roots: std.ArrayList(GlobalNodeId) = .empty,

    pub fn deinit(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) void {
        self.modules.deinit(allocator);
        self.files.deinit(allocator);
        self.declarations.deinit(allocator);
        self.symbols.deinit(allocator);
        self.symbol_declarations.deinit(allocator);
        self.types.deinit(allocator);
        self.functions.deinit(allocator);
        self.bindings.deinit(allocator);
        self.nodes.deinit(allocator);
        self.blocks.deinit(allocator);
        self.block_nodes.deinit(allocator);
        self.fields.deinit(allocator);
        self.variants.deinit(allocator);
        self.generic_arguments.deinit(allocator);
        self.strings.deinit(allocator);
        self.roots.deinit(allocator);
        self.* = .{};
    }

    pub fn text(self: *const GlobalSemanticGraph, range: StringRange) []const u8 {
        return self.strings.items[range.start..][0..range.len];
    }

    pub fn declaration(self: *const GlobalSemanticGraph, id: GlobalDeclId) Declaration {
        return self.declarations.items[@intFromEnum(id)];
    }

    pub fn semanticType(self: *const GlobalSemanticGraph, id: GlobalTypeId) GlobalType {
        return self.types.items[@intFromEnum(id)];
    }

    pub fn function(self: *const GlobalSemanticGraph, id: GlobalFunctionId) Function {
        return self.functions.items[@intFromEnum(id)];
    }

    pub fn binding(self: *const GlobalSemanticGraph, id: GlobalBindingId) Binding {
        return self.bindings.items[@intFromEnum(id)];
    }

    pub fn node(self: *const GlobalSemanticGraph, id: GlobalNodeId) Node {
        return self.nodes.items[@intFromEnum(id)];
    }

    pub fn storageBytes(self: *const GlobalSemanticGraph) usize {
        return self.modules.items.len * @sizeOf(Module) +
            self.files.items.len * @sizeOf(File) +
            self.declarations.items.len * @sizeOf(Declaration) +
            self.symbols.items.len * @sizeOf(Symbol) +
            self.symbol_declarations.items.len * @sizeOf(GlobalDeclId) +
            self.types.items.len * @sizeOf(GlobalType) +
            self.functions.items.len * @sizeOf(Function) +
            self.bindings.items.len * @sizeOf(Binding) +
            self.nodes.items.len * @sizeOf(Node) +
            self.blocks.items.len * @sizeOf(Block) +
            self.block_nodes.items.len * @sizeOf(GlobalNodeId) +
            self.fields.items.len * @sizeOf(Field) +
            self.variants.items.len * @sizeOf(ChoiceVariant) +
            self.generic_arguments.items.len * @sizeOf(GenericTypeArgument) +
            self.strings.items.len +
            self.roots.items.len * @sizeOf(GlobalNodeId);
    }

    pub fn addString(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, value: []const u8) !StringRange {
        return semantic_strings.append(&self.strings, allocator, value);
    }
};

test "global semantic graph owns independent typed tables" {
    const allocator = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const name = try graph.addString(allocator, "Thing");
    try graph.declarations.append(allocator, .{
        .kind = .type,
        .name = name,
        .source = .{ .file_index = 0, .offset = 4 },
        .type_id = @enumFromInt(0),
    });
    try graph.types.append(allocator, .{ .declared = @enumFromInt(0) });

    try std.testing.expectEqualStrings("Thing", graph.text(name));
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(graph.declaration(@enumFromInt(0)).type_id.?));
}
