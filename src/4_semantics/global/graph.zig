const std = @import("std");
const primitives = @import("../primitives/schema.zig");
const semantic_strings = @import("../primitives/strings.zig");
const callable = @import("../primitives/callable.zig");
const type_shapes = @import("../primitives/type_shapes.zig");

pub const GlobalDeclId = enum(u32) { _ };
pub const GlobalTypeId = enum(u32) { _ };
pub const GlobalFunctionId = enum(u32) { _ };
pub const GlobalBindingId = enum(u32) { _ };
pub const GlobalNodeId = enum(u32) { _ };
pub const GlobalBlockId = enum(u32) { _ };
pub const GlobalFieldId = enum(u32) { _ };
pub const GlobalVariantId = enum(u32) { _ };
pub const GlobalGenericArgId = enum(u32) { _ };
pub const GlobalValueFieldId = enum(u32) { _ };
pub const GlobalSwitchCaseId = enum(u32) { _ };
pub const GlobalSwitchId = enum(u32) { _ };
pub const GlobalAutoDeinitFieldId = enum(u32) { _ };
pub const GlobalAutoDeinitId = enum(u32) { _ };
pub const GlobalVirtualRegistryId = enum(u32) { _ };
pub const GlobalVirtualizeId = enum(u32) { _ };
pub const GlobalVirtualCallId = enum(u32) { _ };
pub const GlobalReachSegmentId = enum(u32) { _ };
pub const GlobalReachAlternativeId = enum(u32) { _ };
pub const GlobalReachId = enum(u32) { _ };
pub const GlobalNullableUnwrapId = enum(u32) { _ };
pub const GlobalTestingExpectErrorId = enum(u32) { _ };
pub const GlobalErrorPropagationId = enum(u32) { _ };
pub const GlobalErrorContextId = enum(u32) { _ };
pub const GlobalFileId = enum(u32) { _ };
pub const GlobalModuleId = enum(u32) { _ };

pub const Ids = struct {
    pub const DeclId = GlobalDeclId;
    pub const TypeId = GlobalTypeId;
    pub const FunctionId = GlobalFunctionId;
    pub const BindingId = GlobalBindingId;
    pub const NodeId = GlobalNodeId;
    pub const BlockId = GlobalBlockId;
    pub const FieldId = GlobalFieldId;
    pub const VariantId = GlobalVariantId;
    pub const GenericArgId = GlobalGenericArgId;
    pub const ValueFieldId = GlobalValueFieldId;
    pub const SwitchCaseId = GlobalSwitchCaseId;
    pub const SwitchId = GlobalSwitchId;
    pub const AutoDeinitFieldId = GlobalAutoDeinitFieldId;
    pub const AutoDeinitId = GlobalAutoDeinitId;
    pub const VirtualRegistryId = GlobalVirtualRegistryId;
    pub const VirtualizeId = GlobalVirtualizeId;
    pub const VirtualCallId = GlobalVirtualCallId;
    pub const ReachSegmentId = GlobalReachSegmentId;
    pub const ReachAlternativeId = GlobalReachAlternativeId;
    pub const ReachId = GlobalReachId;
    pub const NullableUnwrapId = GlobalNullableUnwrapId;
    pub const TestingExpectErrorId = GlobalTestingExpectErrorId;
    pub const ErrorPropagationId = GlobalErrorPropagationId;
    pub const ErrorContextId = GlobalErrorContextId;
};

pub const StringRange = primitives.StringRange;
pub const DeclRange = primitives.Range(GlobalDeclId);
pub const BindingRange = primitives.Range(GlobalBindingId);
pub const NodeRange = primitives.Range(GlobalNodeId);
pub const FieldRange = primitives.Range(GlobalFieldId);
pub const VariantRange = primitives.Range(GlobalVariantId);

pub const Declaration = primitives.Declaration(Ids);
pub const GlobalType = primitives.SemanticType(Ids);
pub const GenericInstance = type_shapes.GenericInstance(Ids);
pub const Field = primitives.Field(Ids);
pub const ChoiceVariant = primitives.ChoiceVariant(Ids);
pub const GenericArgument = primitives.GenericArgument(Ids);
pub const Function = primitives.Function(Ids);
pub const Binding = primitives.Binding(Ids);
pub const Block = primitives.Block(Ids);
pub const ValueField = primitives.ValueField(Ids);
pub const SwitchCase = primitives.SwitchCase(Ids);
pub const Switch = primitives.Switch(Ids);
pub const AutoDeinitField = primitives.AutoDeinitField(Ids);
pub const AutoDeinit = primitives.AutoDeinit(Ids);
pub const VirtualMethodRegistry = primitives.VirtualMethodRegistry(Ids);
pub const Virtualize = primitives.Virtualize(Ids);
pub const VirtualCall = primitives.VirtualCall(Ids);
pub const ReachAlternative = primitives.ReachAlternative(Ids);
pub const Reach = primitives.Reach(Ids);
pub const NullableUnwrap = primitives.NullableUnwrap(Ids);
pub const TestingExpectError = primitives.TestingExpectError(Ids);
pub const ErrorPropagation = primitives.ErrorPropagation(Ids);
pub const ErrorContext = primitives.ErrorContext(Ids);
pub const Node = primitives.Node(Ids);

pub const File = struct {
    module: GlobalModuleId,
    path: StringRange,
};

pub const Module = struct {
    dir: StringRange,
    is_bundled_core: bool = false,
    files: primitives.Range(GlobalFileId),
    declarations: DeclRange,
};

/// A source alias linked once to semantic module identity. `dir` remains
/// loader metadata; lookup and dispatch consume `target`, never path strings.
pub const ModuleAlias = struct {
    owner: GlobalModuleId,
    declaration: GlobalDeclId,
    target: GlobalModuleId,
    source: primitives.SourceRef,
};

pub const Symbol = struct {
    name: StringRange,
    declarations: DeclRange,
};

/// Cold identity for a concrete generic function. Runtime call dispatch uses
/// only `GlobalFunctionId`; this record prevents distinct comptime instances
/// with identical runtime signatures from being merged accidentally.
pub const GenericFunctionInstance = struct {
    function: GlobalFunctionId,
    parameterized_declaration: GlobalDeclId,
    arguments: primitives.Range(GlobalGenericArgId),
};

/// Construction-only state for slots whose final GlobalTypeId is already
/// allocated but whose semantic payload is not resolved yet. This state is
/// deliberately separate from `GlobalType`: unresolved is not a language type
/// and therefore must never be encoded as `Any` (or any other valid type).
pub const TypeResolutionState = enum(u8) {
    resolved,
    unresolved,
};

const unresolved_type_poison_decl: GlobalDeclId = @enumFromInt(std.math.maxInt(u32));
const unresolved_binding_type_poison: GlobalTypeId = @enumFromInt(std.math.maxInt(u32));

pub const GlobalSemanticGraph = struct {
    modules: std.ArrayList(Module) = .empty,
    module_aliases: std.ArrayList(ModuleAlias) = .empty,
    files: std.ArrayList(File) = .empty,
    declarations: std.ArrayList(Declaration) = .empty,
    symbols: std.ArrayList(Symbol) = .empty,
    symbol_declarations: std.ArrayList(GlobalDeclId) = .empty,
    types: std.ArrayList(GlobalType) = .empty,
    /// Present only while GlobalSema is resolving preallocated type slots.
    /// Final GlobalSemanticGraph values have this list empty.
    type_resolution: std.ArrayList(TypeResolutionState) = .empty,
    generic_instances: std.ArrayList(GenericInstance) = .empty,
    functions: std.ArrayList(Function) = .empty,
    function_operators: std.ArrayList(?callable.OperatorKind) = .empty,
    generic_function_instances: std.ArrayList(GenericFunctionInstance) = .empty,
    bindings: std.ArrayList(Binding) = .empty,
    /// Present only while GlobalSema is inferring bindings whose type was not
    /// available in ModuleSema. Final graphs always leave this list empty.
    binding_type_resolution: std.ArrayList(TypeResolutionState) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    blocks: std.ArrayList(Block) = .empty,
    fields: std.ArrayList(Field) = .empty,
    variants: std.ArrayList(ChoiceVariant) = .empty,
    generic_arguments: std.ArrayList(GenericArgument) = .empty,
    value_fields: std.ArrayList(ValueField) = .empty,
    switch_cases: std.ArrayList(SwitchCase) = .empty,
    switches: std.ArrayList(Switch) = .empty,
    auto_deinit_fields: std.ArrayList(AutoDeinitField) = .empty,
    auto_deinits: std.ArrayList(AutoDeinit) = .empty,
    virtual_registries: std.ArrayList(VirtualMethodRegistry) = .empty,
    virtualizes: std.ArrayList(Virtualize) = .empty,
    virtual_calls: std.ArrayList(VirtualCall) = .empty,
    reach_segments: std.ArrayList(StringRange) = .empty,
    reach_alternatives: std.ArrayList(ReachAlternative) = .empty,
    reaches: std.ArrayList(Reach) = .empty,
    nullable_unwraps: std.ArrayList(NullableUnwrap) = .empty,
    testing_expect_errors: std.ArrayList(TestingExpectError) = .empty,
    error_propagations: std.ArrayList(ErrorPropagation) = .empty,
    error_contexts: std.ArrayList(ErrorContext) = .empty,

    node_refs: std.ArrayList(GlobalNodeId) = .empty,
    type_refs: std.ArrayList(GlobalTypeId) = .empty,
    binding_refs: std.ArrayList(GlobalBindingId) = .empty,
    function_refs: std.ArrayList(GlobalFunctionId) = .empty,
    virtual_registry_refs: std.ArrayList(GlobalVirtualRegistryId) = .empty,

    strings: std.ArrayList(u8) = .empty,
    roots: std.ArrayList(GlobalNodeId) = .empty,

    pub fn deinit(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) void {
        inline for (.{
            &self.modules,               &self.module_aliases,        &self.files,                      &self.declarations,
            &self.symbols,
            &self.symbol_declarations,   &self.types,                 &self.type_resolution,            &self.generic_instances,
            &self.functions,             &self.function_operators,    &self.generic_function_instances, &self.bindings,
            &self.binding_type_resolution,
            &self.nodes,                 &self.blocks,                &self.fields,                     &self.variants,
            &self.generic_arguments,     &self.value_fields,          &self.switch_cases,               &self.switches,
            &self.auto_deinit_fields,    &self.auto_deinits,          &self.virtual_registries,         &self.virtualizes,
            &self.virtual_calls,         &self.reach_segments,        &self.reach_alternatives,         &self.reaches,
            &self.nullable_unwraps,      &self.testing_expect_errors, &self.error_propagations,         &self.error_contexts,
            &self.node_refs,             &self.type_refs,             &self.binding_refs,               &self.function_refs,
            &self.virtual_registry_refs, &self.strings,               &self.roots,
        }) |list| list.deinit(allocator);
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

    /// Returns null while a preallocated global type slot is unresolved. Code
    /// that participates in GlobalSema should prefer this over reading `types`
    /// directly; final consumers see no unresolved slots.
    pub fn resolvedSemanticType(self: *const GlobalSemanticGraph, id: GlobalTypeId) ?GlobalType {
        if (self.isTypeUnresolved(id)) return null;
        return self.types.items[@intFromEnum(id)];
    }

    pub fn isTypeUnresolved(self: *const GlobalSemanticGraph, id: GlobalTypeId) bool {
        const raw: usize = @intFromEnum(id);
        return raw < self.type_resolution.items.len and self.type_resolution.items[raw] == .unresolved;
    }

    /// Mark a preallocated slot as unresolved and replace the old semantic
    /// sentinel with a deliberately invalid payload. Resolution state, rather
    /// than the payload, is authoritative while GlobalSema is running.
    pub fn markTypeUnresolved(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalTypeId) !void {
        const raw: usize = @intFromEnum(id);
        if (raw >= self.types.items.len) return error.InvalidGlobalTypeId;
        try self.ensureTypeResolutionCovers(allocator, self.types.items.len);
        self.type_resolution.items[raw] = .unresolved;
        self.types.items[raw] = .{ .declared = unresolved_type_poison_decl };
    }

    /// Existing resolvers still patch preallocated slots directly. Until those
    /// writes all go through one mutation API, reconcile construction state by
    /// observing that the poison payload has been replaced.
    pub fn reconcileTypeResolution(self: *GlobalSemanticGraph) bool {
        var changed = false;
        const limit = @min(self.type_resolution.items.len, self.types.items.len);
        for (self.type_resolution.items[0..limit], 0..) |*state, raw| {
            if (state.* != .unresolved or isUnresolvedTypePoison(self.types.items[raw])) continue;
            state.* = .resolved;
            changed = true;
        }
        return changed;
    }

    pub fn hasUnresolvedTypes(self: *const GlobalSemanticGraph) bool {
        for (self.type_resolution.items) |state| if (state == .unresolved) return true;
        return false;
    }

    /// Construction metadata is not part of the durable GlobalSG. Calling this
    /// before every slot is resolved is an error rather than silently exposing
    /// a provisional graph to Safety, Codegen or the LSP.
    pub fn finishTypeResolution(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) !void {
        if (self.hasUnresolvedTypes()) return error.UnresolvedGlobalTypeSlots;
        self.type_resolution.deinit(allocator);
        self.type_resolution = .empty;
    }

    fn ensureTypeResolutionCovers(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, count: usize) !void {
        if (self.type_resolution.items.len >= count) return;
        try self.type_resolution.ensureTotalCapacity(allocator, count);
        while (self.type_resolution.items.len < count) self.type_resolution.appendAssumeCapacity(.resolved);
    }

    pub fn function(self: *const GlobalSemanticGraph, id: GlobalFunctionId) Function {
        return self.functions.items[@intFromEnum(id)];
    }

    pub fn functionOperator(self: *const GlobalSemanticGraph, id: GlobalFunctionId) ?callable.OperatorKind {
        return self.function_operators.items[@intFromEnum(id)];
    }

    pub fn binding(self: *const GlobalSemanticGraph, id: GlobalBindingId) Binding {
        return self.bindings.items[@intFromEnum(id)];
    }

    pub fn isBindingTypeUnresolved(self: *const GlobalSemanticGraph, id: GlobalBindingId) bool {
        const raw: usize = @intFromEnum(id);
        return raw < self.binding_type_resolution.items.len and self.binding_type_resolution.items[raw] == .unresolved;
    }

    pub fn markBindingTypeUnresolved(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalBindingId) !void {
        const raw: usize = @intFromEnum(id);
        if (raw >= self.bindings.items.len) return error.InvalidGlobalBindingId;
        try self.ensureBindingTypeResolutionCovers(allocator, self.bindings.items.len);
        self.binding_type_resolution.items[raw] = .unresolved;
        self.bindings.items[raw].ty = unresolved_binding_type_poison;
    }

    pub fn reconcileBindingTypeResolution(self: *GlobalSemanticGraph) bool {
        var changed = false;
        const limit = @min(self.binding_type_resolution.items.len, self.bindings.items.len);
        for (self.binding_type_resolution.items[0..limit], 0..) |*state, raw| {
            if (state.* != .unresolved or self.bindings.items[raw].ty == unresolved_binding_type_poison) continue;
            state.* = .resolved;
            changed = true;
        }
        return changed;
    }

    pub fn hasUnresolvedBindingTypes(self: *const GlobalSemanticGraph) bool {
        for (self.binding_type_resolution.items) |state| if (state == .unresolved) return true;
        return false;
    }

    pub fn finishBindingTypeResolution(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) !void {
        if (self.hasUnresolvedBindingTypes()) return error.UnresolvedGlobalBindingTypes;
        self.binding_type_resolution.deinit(allocator);
        self.binding_type_resolution = .empty;
    }

    fn ensureBindingTypeResolutionCovers(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, count: usize) !void {
        if (self.binding_type_resolution.items.len >= count) return;
        try self.binding_type_resolution.ensureTotalCapacity(allocator, count);
        while (self.binding_type_resolution.items.len < count) self.binding_type_resolution.appendAssumeCapacity(.resolved);
    }

    pub fn node(self: *const GlobalSemanticGraph, id: GlobalNodeId) Node {
        return self.nodes.items[@intFromEnum(id)];
    }

    pub fn moduleForDeclaration(self: *const GlobalSemanticGraph, id: GlobalDeclId) ?GlobalModuleId {
        const raw = @intFromEnum(id);
        for (self.modules.items, 0..) |module, index| {
            const start: usize = module.declarations.start;
            const end = start + module.declarations.len;
            if (raw >= start and raw < end) return @enumFromInt(@as(u32, @intCast(index)));
        }
        return null;
    }

    pub fn moduleForSymbol(self: *const GlobalSemanticGraph, symbol: Symbol) ?GlobalModuleId {
        if (symbol.declarations.len == 0) return null;
        const first = self.symbol_declarations.items[symbol.declarations.start];
        return self.moduleForDeclaration(first);
    }

    pub fn addString(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, value: []const u8) !StringRange {
        return semantic_strings.append(&self.strings, allocator, value);
    }

    pub fn storageBytes(self: *const GlobalSemanticGraph) usize {
        return self.modules.items.len * @sizeOf(Module) +
            self.module_aliases.items.len * @sizeOf(ModuleAlias) +
            self.files.items.len * @sizeOf(File) +
            self.declarations.items.len * @sizeOf(Declaration) +
            self.symbols.items.len * @sizeOf(Symbol) +
            self.symbol_declarations.items.len * @sizeOf(GlobalDeclId) +
            self.types.items.len * @sizeOf(GlobalType) +
            self.type_resolution.items.len * @sizeOf(TypeResolutionState) +
            self.generic_instances.items.len * @sizeOf(GenericInstance) +
            self.functions.items.len * @sizeOf(Function) +
            self.function_operators.items.len * @sizeOf(?callable.OperatorKind) +
            self.generic_function_instances.items.len * @sizeOf(GenericFunctionInstance) +
            self.bindings.items.len * @sizeOf(Binding) +
            self.binding_type_resolution.items.len * @sizeOf(TypeResolutionState) +
            self.nodes.items.len * @sizeOf(Node) +
            self.blocks.items.len * @sizeOf(Block) +
            self.fields.items.len * @sizeOf(Field) +
            self.variants.items.len * @sizeOf(ChoiceVariant) +
            self.generic_arguments.items.len * @sizeOf(GenericArgument) +
            self.value_fields.items.len * @sizeOf(ValueField) +
            self.switch_cases.items.len * @sizeOf(SwitchCase) +
            self.switches.items.len * @sizeOf(Switch) +
            self.auto_deinit_fields.items.len * @sizeOf(AutoDeinitField) +
            self.auto_deinits.items.len * @sizeOf(AutoDeinit) +
            self.virtual_registries.items.len * @sizeOf(VirtualMethodRegistry) +
            self.virtualizes.items.len * @sizeOf(Virtualize) +
            self.virtual_calls.items.len * @sizeOf(VirtualCall) +
            self.reach_segments.items.len * @sizeOf(StringRange) +
            self.reach_alternatives.items.len * @sizeOf(ReachAlternative) +
            self.reaches.items.len * @sizeOf(Reach) +
            self.nullable_unwraps.items.len * @sizeOf(NullableUnwrap) +
            self.testing_expect_errors.items.len * @sizeOf(TestingExpectError) +
            self.error_propagations.items.len * @sizeOf(ErrorPropagation) +
            self.error_contexts.items.len * @sizeOf(ErrorContext) +
            self.node_refs.items.len * @sizeOf(GlobalNodeId) +
            self.type_refs.items.len * @sizeOf(GlobalTypeId) +
            self.binding_refs.items.len * @sizeOf(GlobalBindingId) +
            self.function_refs.items.len * @sizeOf(GlobalFunctionId) +
            self.virtual_registry_refs.items.len * @sizeOf(GlobalVirtualRegistryId) +
            self.strings.items.len + self.roots.items.len * @sizeOf(GlobalNodeId);
    }
};

fn isUnresolvedTypePoison(value: GlobalType) bool {
    return switch (value) {
        .declared => |decl| decl == unresolved_type_poison_decl,
        else => false,
    };
}

test "global semantic graph derives symbol module ownership from declarations" {
    const allocator = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const module_name = try graph.addString(allocator, "demo");
    const type_name = try graph.addString(allocator, "Thing");
    try graph.modules.append(allocator, .{
        .dir = module_name,
        .files = .{ .start = 0, .len = 0 },
        .declarations = .{ .start = 0, .len = 1 },
    });
    try graph.declarations.append(allocator, .{
        .kind = .type,
        .name = type_name,
        .source = .{ .file_index = 0, .offset = 4 },
        .type_id = @enumFromInt(0),
    });
    try graph.types.append(allocator, .{ .declared = @enumFromInt(0) });
    try graph.symbol_declarations.append(allocator, @enumFromInt(0));
    const symbol = Symbol{ .name = type_name, .declarations = .{ .start = 0, .len = 1 } };
    try graph.symbols.append(allocator, symbol);
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
    });
    try graph.function_operators.append(allocator, .add);

    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(graph.moduleForSymbol(symbol).?));
    try std.testing.expectEqualStrings("Thing", graph.text(type_name));
    try std.testing.expectEqual(callable.OperatorKind.add, graph.functionOperator(@enumFromInt(0)).?);
}

test "unresolved global type slots are construction state, not Any" {
    const allocator = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    try graph.types.append(allocator, .{ .builtin = .Any });
    try graph.markTypeUnresolved(allocator, @enumFromInt(0));
    try std.testing.expect(graph.isTypeUnresolved(@enumFromInt(0)));
    try std.testing.expect(graph.resolvedSemanticType(@enumFromInt(0)) == null);
    try std.testing.expectError(error.UnresolvedGlobalTypeSlots, graph.finishTypeResolution(allocator));

    graph.types.items[0] = .{ .builtin = .Int32 };
    try std.testing.expect(graph.reconcileTypeResolution());
    try std.testing.expect(!graph.hasUnresolvedTypes());
    try graph.finishTypeResolution(allocator);
    try std.testing.expectEqual(@as(usize, 0), graph.type_resolution.items.len);
}
