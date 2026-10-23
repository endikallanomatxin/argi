const std = @import("std");
const primitives = @import("../primitives/schema.zig");
const semantic_strings = @import("../primitives/strings.zig");
const type_shapes = @import("../primitives/type_shapes.zig");
const module_sg = @import("../module/graph.zig");

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
pub const BlockAssumptions = primitives.BlockAssumptions(Ids);
pub const ValueField = primitives.ValueField(Ids);
pub const SwitchCase = primitives.SwitchCase(Ids);
pub const Switch = primitives.Switch(Ids);
pub const AutoDeinitField = primitives.AutoDeinitField(Ids);
pub const AutoDeinit = primitives.AutoDeinit(Ids);
pub const VirtualMethodRegistry = primitives.VirtualMethodRegistry(Ids);
pub const Virtualize = primitives.Virtualize(Ids);
pub const VirtualCall = primitives.VirtualCall(Ids);
/// Static contract selection checks the declaration without creating runtime
/// erasure. This metadata is recorded transactionally with selected functions
/// and consumed after their safety summaries converge.
pub const ContractSafetyConformance = struct {
    selection: primitives.ContractOperationIdentity,
    method: GlobalFunctionId,
    contract: primitives.MethodSafetyContract,
    receiver_input_index: ?u32,
    domains: []const primitives.StorageDomainMapping = &.{},
    source: primitives.SourceRef,
};
// Static conformance evidence owns canonical declaration-order arguments. It has no
// erased receiver and participates in the ordinary append-only checkpoints.
pub const ContractOperationBindingId = enum(u32) { _ };
pub const ContractOperationBinding = struct {
    contract_declaration: GlobalDeclId,
    requirement_index: u32,
    requirement_source: primitives.SourceRef,
    implementation_source: primitives.SourceRef,
    alias_source: ?primitives.SourceRef = null,
    name: StringRange,
    declaration: GlobalDeclId,
    instantiate_associated: bool = false,
};
pub const ContractConformance = struct {
    // Declaration/signature validation is separate from the later safety proof.
    declaration_validated: bool = false,
    implementation_arguments: primitives.Range(GlobalGenericArgId) = .{ .start = 0, .len = 0 },
    operation_bindings: primitives.Range(ContractOperationBindingId) = .{ .start = 0, .len = 0 },
    context: GlobalModuleId = @enumFromInt(0),
    declaration: GlobalDeclId,
    participants: primitives.Range(GlobalGenericArgId),
    associated_arguments: primitives.Range(GlobalGenericArgId),
    operations: primitives.Range(GlobalFunctionId) = .{ .start = 0, .len = 0 },
    source: primitives.SourceRef,
};
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
    // Original source version; null only for synthetic graphs without a buffer.
    content_hash: ?u64 = null,
};

pub const Module = struct {
    dir: StringRange,
    // Explicit appended source fragment; physical ranges remain unchanged.
    namespace: ?GlobalModuleId = null,
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

pub const ParameterizedFunctionCandidate = struct {
    module_index: u32,
    function_index: u32,
};

/// Construction-only state for slots whose final GlobalTypeId is already
/// allocated but whose semantic payload is not resolved yet. This state is
/// deliberately separate from `GlobalType`: unresolved is not a language type
/// and therefore must never be encoded as `Any` (or any other valid type).
pub const TypeResolutionState = enum(u8) {
    resolved,
    unresolved,
};

pub const unresolved_type_poison_decl: GlobalDeclId = @enumFromInt(std.math.maxInt(u32));
const unresolved_binding_type_poison: GlobalTypeId = @enumFromInt(std.math.maxInt(u32));

pub const ArgumentDefaultTemporary = struct { expression: GlobalNodeId, declaration: GlobalNodeId };
pub const ArgumentDefaultBinding = struct { ty: ?GlobalTypeId, integer: ?i64 };
pub const ArgumentDefault = struct {
    module_index: usize,
    expression: @import("../module/parameterized/ir.zig").ParameterizedNodeId,
    bindings: primitives.Range(u32),
};

pub const GlobalSemanticGraph = struct {
    pub const Checkpoint = struct {
        pool_lengths: [@typeInfo(GlobalSemanticGraph).@"struct".fields.len]usize,
        indexed_functions: usize,
        indexed_declarations: usize,
        type_resolution_len: usize,
        binding_type_resolution_len: usize,
        type_argument_rewrites_len: usize,
    };

    const ConstructionState = struct {
        type_resolution: std.ArrayList(TypeResolutionState) = .empty,
        binding_type_resolution: std.ArrayList(TypeResolutionState) = .empty,
        type_argument_rewrites: std.ArrayList(struct {
            type_id: GlobalTypeId,
            previous: primitives.Range(GlobalGenericArgId),
        }) = .empty,

        fn deinit(self: *ConstructionState, allocator: std.mem.Allocator) void {
            self.type_resolution.deinit(allocator);
            self.binding_type_resolution.deinit(allocator);
            self.type_argument_rewrites.deinit(allocator);
            self.* = .{};
        }
    };

    const LookupState = struct {
        function_names: std.StringHashMapUnmanaged(std.ArrayList(GlobalFunctionId)) = .empty,
        indexed_functions: usize = 0,
        declaration_names: std.StringHashMapUnmanaged(std.ArrayList(GlobalDeclId)) = .empty,
        indexed_declarations: usize = 0,
        parameterized_function_names: std.StringHashMapUnmanaged(std.ArrayList(ParameterizedFunctionCandidate)) = .empty,
        indexed_parameterized_modules: usize = 0,
        indexed_module_functions: usize = 0,

        fn deinit(self: *LookupState, allocator: std.mem.Allocator) void {
            var functions = self.function_names.iterator();
            while (functions.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            self.function_names.deinit(allocator);
            var declarations = self.declaration_names.iterator();
            while (declarations.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            self.declaration_names.deinit(allocator);

            var parameterized = self.parameterized_function_names.iterator();
            while (parameterized.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            self.parameterized_function_names.deinit(allocator);
            self.* = .{};
        }
    };

    target: @import("../../1_base/target.zig").Config = .{},
    modules: std.ArrayList(Module) = .empty,
    module_aliases: std.ArrayList(ModuleAlias) = .empty,
    files: std.ArrayList(File) = .empty,
    declarations: std.ArrayList(Declaration) = .empty,
    symbols: std.ArrayList(Symbol) = .empty,
    symbol_declarations: std.ArrayList(GlobalDeclId) = .empty,
    types: std.ArrayList(GlobalType) = .empty,
    generic_instances: std.ArrayList(GenericInstance) = .empty,
    functions: std.ArrayList(Function) = .empty,
    generic_function_instances: std.ArrayList(GenericFunctionInstance) = .empty,
    bindings: std.ArrayList(Binding) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    comptime_requests: std.ArrayList(GlobalNodeId) = .empty,
    blocks: std.ArrayList(Block) = .empty,
    block_assumptions: std.ArrayList(BlockAssumptions) = .empty,
    fields: std.ArrayList(Field) = .empty,
    variants: std.ArrayList(ChoiceVariant) = .empty,
    generic_arguments: std.ArrayList(GenericArgument) = .empty,
    argument_defaults: std.ArrayList(ArgumentDefault) = .empty,
    argument_default_temporaries: std.ArrayList(ArgumentDefaultTemporary) = .empty,
    argument_default_bindings: std.ArrayList(ArgumentDefaultBinding) = .empty,
    value_fields: std.ArrayList(ValueField) = .empty,
    switch_cases: std.ArrayList(SwitchCase) = .empty,
    switches: std.ArrayList(Switch) = .empty,
    auto_deinit_fields: std.ArrayList(AutoDeinitField) = .empty,
    auto_deinits: std.ArrayList(AutoDeinit) = .empty,
    virtual_registries: std.ArrayList(VirtualMethodRegistry) = .empty,
    virtualizes: std.ArrayList(Virtualize) = .empty,
    contract_safety_conformances: std.ArrayList(ContractSafetyConformance) = .empty,
    contract_conformances: std.ArrayList(ContractConformance) = .empty,
    contract_operation_bindings: std.ArrayList(ContractOperationBinding) = .empty,
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

    // Resolved safety selectors contain immutable nested slices. Their arena
    // belongs to this graph and is copied on publication, never borrowed from
    // a speculative graph that may be discarded.
    safety_arena: ?*std.heap.ArenaAllocator = null,

    // Transient lookup state used while building/querying GlobalSema. The
    // append-only semantic pools remain the source of truth; these indexes are
    // derived state and are not part of a persistent semantic representation.
    lookup: LookupState = .{},

    // Construction-only resolution state. Final graphs empty these tables
    // before they are exposed to Safety, Codegen or the LSP.
    construction: ConstructionState = .{},

    pub fn safetyAllocator(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) !std.mem.Allocator {
        if (self.safety_arena == null) {
            const arena = try allocator.create(std.heap.ArenaAllocator);
            arena.* = .init(allocator);
            self.safety_arena = arena;
        }
        return self.safety_arena.?.allocator();
    }

    fn copySafetyOutcomes(allocator: std.mem.Allocator, source: []const primitives.MethodSafetyContract.Outcome) anyerror![]const primitives.MethodSafetyContract.Outcome {
        const result = try allocator.dupe(primitives.MethodSafetyContract.Outcome, source);
        for (result) |*outcome| {
            outcome.parent_variants = try allocator.dupe(u32, outcome.parent_variants);
            outcome.outcomes = try copySafetyOutcomes(allocator, outcome.outcomes);
        }
        return result;
    }

    /// Copy mutable semantic pools while preserving every existing identity.
    /// Immutable source metadata keeps its original ModuleSG lifetime. Derived
    /// name indexes are rebuilt lazily in the copy. Ordinary compilation does
    /// not call this; retained-session publication can isolate speculative edits.
    pub fn clone(self: *const GlobalSemanticGraph, allocator: std.mem.Allocator) !GlobalSemanticGraph {
        var result: GlobalSemanticGraph = .{ .target = self.target };
        errdefer result.deinit(allocator);
        inline for (@typeInfo(GlobalSemanticGraph).@"struct".fields) |field| {
            if (comptime switch (@typeInfo(field.type)) {
                .@"struct" => @hasField(field.type, "items"),
                else => false,
            }) try @field(result, field.name).appendSlice(allocator, @field(self, field.name).items);
        }
        for (result.virtual_registries.items) |*registry| if (registry.safety_contract) |*contract| {
            contract.outcomes = try copySafetyOutcomes(try result.safetyAllocator(allocator), contract.outcomes);
        };
        for (result.contract_safety_conformances.items) |*conformance| {
            conformance.contract.outcomes = try copySafetyOutcomes(try result.safetyAllocator(allocator), conformance.contract.outcomes);
        }
        inline for (@typeInfo(ConstructionState).@"struct".fields) |field| {
            try @field(result.construction, field.name).appendSlice(allocator, @field(self.construction, field.name).items);
        }
        return result;
    }

    /// Release growth room in a finalized retained snapshot without moving any
    /// element. Allocators may decline; keep the original allocation in that
    /// case. Never use a reallocating shrink on published metadata pointers.
    pub fn trimPoolCapacity(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) void {
        inline for (@typeInfo(GlobalSemanticGraph).@"struct".fields) |field| {
            if (comptime switch (@typeInfo(field.type)) {
                .@"struct" => @hasField(field.type, "items") and @hasField(field.type, "capacity"),
                else => false,
            }) {
                const pool = &@field(self, field.name);
                if (pool.capacity > pool.items.len and allocator.resize(pool.allocatedSlice(), pool.items.len))
                    pool.capacity = pool.items.len;
            }
        }
    }

    /// Snapshot append-only graph storage and the mutable lookup-index tails.
    /// This is deliberately not a transaction for resolver-local caches or
    /// side effects; callers must checkpoint those separately when needed.
    pub fn checkpoint(self: *const GlobalSemanticGraph) Checkpoint {
        const pools = @typeInfo(GlobalSemanticGraph).@"struct".fields;
        var result: Checkpoint = .{
            .pool_lengths = undefined,
            .indexed_functions = self.lookup.indexed_functions,
            .indexed_declarations = self.lookup.indexed_declarations,
            .type_resolution_len = self.construction.type_resolution.items.len,
            .binding_type_resolution_len = self.construction.binding_type_resolution.items.len,
            .type_argument_rewrites_len = self.construction.type_argument_rewrites.items.len,
        };
        inline for (pools, 0..) |pool, index| if (comptime switch (@typeInfo(pool.type)) {
            .@"struct" => @hasField(pool.type, "items"),
            else => false,
        }) {
            result.pool_lengths[index] = @field(self, pool.name).items.len;
        };
        return result;
    }

    /// Drop indexed IDs before truncating the append-only pools they reference.
    /// Canonical generic argument rewrites are restored before their pools shrink.
    /// Other in-place mutations of pre-existing entries remain outside this checkpoint.
    pub fn rollback(self: *GlobalSemanticGraph, saved: Checkpoint) void {
        const pools = @typeInfo(GlobalSemanticGraph).@"struct".fields;
        self.discardIndexedTail(saved.indexed_functions, saved.indexed_declarations);
        while (self.construction.type_argument_rewrites.items.len > saved.type_argument_rewrites_len) {
            const rewrite = self.construction.type_argument_rewrites.pop().?;
            self.types.items[@intFromEnum(rewrite.type_id)].generic.arguments = rewrite.previous;
        }
        self.construction.type_resolution.shrinkRetainingCapacity(saved.type_resolution_len);
        self.construction.binding_type_resolution.shrinkRetainingCapacity(saved.binding_type_resolution_len);
        inline for (pools, 0..) |pool, index| if (comptime switch (@typeInfo(pool.type)) {
            .@"struct" => @hasField(pool.type, "items"),
            else => false,
        }) {
            @field(self, pool.name).shrinkRetainingCapacity(saved.pool_lengths[index]);
        };
    }

    pub fn deinit(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) void {
        self.lookup.deinit(allocator);
        self.construction.deinit(allocator);
        if (self.safety_arena) |arena| {
            arena.deinit();
            allocator.destroy(arena);
        }
        inline for (.{
            &self.modules,                     &self.module_aliases,             &self.files,                        &self.declarations,
            &self.symbols,                     &self.symbol_declarations,        &self.types,                        &self.generic_instances,
            &self.functions,                   &self.generic_function_instances, &self.bindings,                     &self.nodes,
            &self.blocks,                      &self.fields,                     &self.variants,                     &self.generic_arguments,
            &self.value_fields,                &self.switch_cases,               &self.switches,                     &self.auto_deinit_fields,
            &self.auto_deinits,                &self.virtual_registries,         &self.virtualizes,                  &self.virtual_calls,
            &self.reach_segments,              &self.reach_alternatives,         &self.reaches,                      &self.nullable_unwraps,
            &self.testing_expect_errors,       &self.error_propagations,         &self.error_contexts,               &self.node_refs,
            &self.type_refs,                   &self.binding_refs,               &self.function_refs,                &self.virtual_registry_refs,
            &self.strings,                     &self.roots,                      &self.contract_safety_conformances, &self.contract_conformances,
            &self.contract_operation_bindings, &self.argument_defaults,          &self.argument_default_temporaries, &self.argument_default_bindings,
            &self.comptime_requests,           &self.block_assumptions,
        }) |list| list.deinit(allocator);
        self.* = .{};
    }

    pub fn declarationSourceName(self: *const GlobalSemanticGraph, id: GlobalDeclId) StringRange {
        for (self.contract_operation_bindings.items) |operation_binding|
            if (operation_binding.instantiate_associated and operation_binding.declaration == id) return operation_binding.name;
        return self.declaration(id).name;
    }

    pub fn callOperation(self: *const GlobalSemanticGraph, call: anytype) ?primitives.ContractOperationIdentity {
        _ = self;
        if (call.contract_operation.conformance == std.math.maxInt(u32)) return null;
        return call.contract_operation;
    }

    pub fn callSourceName(self: *const GlobalSemanticGraph, call: anytype) StringRange {
        if (self.callOperation(call)) |identity| {
            const selected = @import("contract_evidence.zig").selectedOperation(self, identity) orelse unreachable;
            return selected.binding.name;
        }
        return self.declarationSourceName(self.function(call.callee).declaration);
    }

    pub fn text(self: *const GlobalSemanticGraph, range: StringRange) []const u8 {
        return self.strings.items[range.start..][0..range.len];
    }

    fn isNamedFunction(callable: Function) bool {
        return !callable.flags.is_generic_instantiation and !callable.flags.is_c_function_pointer;
    }

    /// Named lookup indexes callable declarations, never cached specializations
    /// or C callback prototypes. Concrete instances keep their FunctionIds.
    pub fn functionsNamed(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, name: []const u8) ![]const GlobalFunctionId {
        while (self.lookup.indexed_functions < self.functions.items.len) {
            const raw = self.lookup.indexed_functions;
            const callable = self.functions.items[raw];
            if (!isNamedFunction(callable)) {
                self.lookup.indexed_functions += 1;
                continue;
            }
            const decl = self.declarations.items[@intFromEnum(callable.declaration)];
            const spelling = self.text(decl.name);
            if (self.lookup.function_names.getPtr(spelling) == null) {
                const owned = try allocator.dupe(u8, spelling);
                self.lookup.function_names.put(allocator, owned, .empty) catch |err| {
                    allocator.free(owned);
                    return err;
                };
            }
            try self.lookup.function_names.getPtr(spelling).?.append(allocator, @enumFromInt(@as(u32, @intCast(raw))));

            self.lookup.indexed_functions += 1;
        }
        return if (self.lookup.function_names.get(name)) |matches| matches.items else &.{};
    }

    pub fn declarationsNamed(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, name: []const u8) ![]const GlobalDeclId {
        while (self.lookup.indexed_declarations < self.declarations.items.len) {
            const raw = self.lookup.indexed_declarations;
            const spelling = self.text(self.declarations.items[raw].name);
            if (self.lookup.declaration_names.getPtr(spelling) == null) {
                const owned = try allocator.dupe(u8, spelling);
                self.lookup.declaration_names.put(allocator, owned, .empty) catch |err| {
                    allocator.free(owned);
                    return err;
                };
            }
            try self.lookup.declaration_names.getPtr(spelling).?.append(allocator, @enumFromInt(@as(u32, @intCast(raw))));
            self.lookup.indexed_declarations += 1;
        }
        return if (self.lookup.declaration_names.get(name)) |matches| matches.items else &.{};
    }

    /// Read an already complete name index without allocating during queries.
    /// A null result asks the caller to use its ordinary traversal instead.
    pub fn indexedDeclarationsNamed(self: *const GlobalSemanticGraph, name: []const u8) ?[]const GlobalDeclId {
        if (self.lookup.indexed_declarations != self.declarations.items.len) return null;
        return if (self.lookup.declaration_names.get(name)) |matches| matches.items else &.{};
    }

    /// Speculative resolution can append functions and declarations before
    /// rolling their pools back. Remove those IDs before truncating the pools.
    pub fn discardIndexedTail(self: *GlobalSemanticGraph, function_count: usize, declaration_count: usize) void {
        while (self.lookup.indexed_functions > function_count) {
            self.lookup.indexed_functions -= 1;
            const entry = self.functions.items[self.lookup.indexed_functions];
            if (!isNamedFunction(entry)) continue;
            const name = self.text(self.declarations.items[@intFromEnum(entry.declaration)].name);
            _ = self.lookup.function_names.getPtr(name).?.pop();
        }
        while (self.lookup.indexed_declarations > declaration_count) {
            self.lookup.indexed_declarations -= 1;
            const name = self.text(self.declarations.items[self.lookup.indexed_declarations].name);
            _ = self.lookup.declaration_names.getPtr(name).?.pop();
        }
    }

    /// Retained modules are immutable; newly appended modules extend this
    /// index. Keep a template cursor so allocation failure can resume without
    /// duplicating candidates already published for the current module.
    pub fn parameterizedFunctionsNamed(
        self: *GlobalSemanticGraph,
        allocator: std.mem.Allocator,
        modules: []const module_sg.ModuleSemanticGraph,
        name: []const u8,
    ) ![]const ParameterizedFunctionCandidate {
        std.debug.assert(self.lookup.indexed_parameterized_modules <= modules.len);
        while (self.lookup.indexed_parameterized_modules < modules.len) {
            const module_index = self.lookup.indexed_parameterized_modules;
            const module = &modules[module_index];
            const templates = module.semantic.parameterized_storage.parameterized_functions.items;
            while (self.lookup.indexed_module_functions < templates.len) {
                const function_index = self.lookup.indexed_module_functions;
                const candidate = templates[function_index];
                if (candidate.concrete_function != null) {
                    self.lookup.indexed_module_functions += 1;
                    continue;
                }
                const spelling = module.text(module.declarations.items[@intFromEnum(candidate.declaration)].name);
                if (self.lookup.parameterized_function_names.getPtr(spelling) == null) {
                    const owned = try allocator.dupe(u8, spelling);
                    self.lookup.parameterized_function_names.put(allocator, owned, .empty) catch |err| {
                        allocator.free(owned);
                        return err;
                    };
                }

                try self.lookup.parameterized_function_names.getPtr(spelling).?.append(allocator, .{
                    .module_index = @intCast(module_index),
                    .function_index = @intCast(function_index),
                });
                self.lookup.indexed_module_functions += 1;
            }
            self.lookup.indexed_parameterized_modules += 1;
            self.lookup.indexed_module_functions = 0;
        }
        return if (self.lookup.parameterized_function_names.get(name)) |matches| matches.items else &.{};
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
        return raw < self.construction.type_resolution.items.len and self.construction.type_resolution.items[raw] == .unresolved;
    }

    /// Mark a preallocated slot as unresolved and replace the old semantic
    /// sentinel with a deliberately invalid payload. Resolution state, rather
    /// than the payload, is authoritative while GlobalSema is running.
    pub fn markTypeUnresolved(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalTypeId) !void {
        const raw: usize = @intFromEnum(id);
        if (raw >= self.types.items.len) return error.InvalidGlobalTypeId;
        try self.ensureTypeResolutionCovers(allocator, self.types.items.len);
        self.construction.type_resolution.items[raw] = .unresolved;
        self.types.items[raw] = .{ .declared = unresolved_type_poison_decl };
    }

    /// Publish a type through the construction-state boundary. Type holes must
    /// be resolved through this API so GlobalSema never needs to rediscover
    /// direct slot writes with a full-pool reconciliation scan.
    pub fn resolveType(self: *GlobalSemanticGraph, id: GlobalTypeId, value: GlobalType) !void {
        const raw: usize = @intFromEnum(id);
        if (raw >= self.types.items.len) return error.InvalidGlobalTypeId;
        self.types.items[raw] = value;
        if (raw < self.construction.type_resolution.items.len)
            self.construction.type_resolution.items[raw] = .resolved;
    }

    /// Keep canonicalization of existing types transactional: the new argument
    /// range may belong to an append-only pool that a speculative probe rolls back.
    pub fn replaceTypeArguments(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalTypeId, arguments: primitives.Range(GlobalGenericArgId)) !void {
        const raw: usize = @intFromEnum(id);
        if (raw >= self.types.items.len or self.types.items[raw] != .generic) return error.InvalidGlobalTypeId;
        const previous = self.types.items[raw].generic.arguments;
        if (previous.start == arguments.start and previous.len == arguments.len) return;
        try self.construction.type_argument_rewrites.append(allocator, .{ .type_id = id, .previous = previous });
        self.types.items[raw].generic.arguments = arguments;
    }

    pub fn hasUnresolvedTypes(self: *const GlobalSemanticGraph) bool {
        for (self.construction.type_resolution.items) |state| if (state == .unresolved) return true;
        return false;
    }

    /// Construction metadata is not part of the durable GlobalSG. Calling this
    /// before every slot is resolved is an error rather than silently exposing
    /// a provisional graph to Safety, Codegen or the LSP.
    pub fn finishTypeResolution(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) !void {
        if (self.hasUnresolvedTypes()) return error.UnresolvedGlobalTypeSlots;
        self.construction.type_resolution.deinit(allocator);
        self.construction.type_resolution = .empty;
        self.construction.type_argument_rewrites.deinit(allocator);
        self.construction.type_argument_rewrites = .empty;
    }

    fn ensureTypeResolutionCovers(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, count: usize) !void {
        if (self.construction.type_resolution.items.len >= count) return;
        try self.construction.type_resolution.ensureTotalCapacity(allocator, count);
        while (self.construction.type_resolution.items.len < count) self.construction.type_resolution.appendAssumeCapacity(.resolved);
    }

    pub fn function(self: *const GlobalSemanticGraph, id: GlobalFunctionId) Function {
        return self.functions.items[@intFromEnum(id)];
    }

    pub fn binding(self: *const GlobalSemanticGraph, id: GlobalBindingId) Binding {
        return self.bindings.items[@intFromEnum(id)];
    }

    /// Root bindings have module storage, which outlives function calls.
    /// Codegen predeclares the same roots as LLVM globals.
    pub fn isModuleBinding(self: *const GlobalSemanticGraph, id: GlobalBindingId) bool {
        for (self.roots.items) |root| switch (self.node(root).content) {
            .binding_declaration => |binding_id| if (binding_id == id) return true,
            else => {},
        };
        return false;
    }

    pub fn isBindingTypeUnresolved(self: *const GlobalSemanticGraph, id: GlobalBindingId) bool {
        const raw: usize = @intFromEnum(id);
        return raw < self.construction.binding_type_resolution.items.len and self.construction.binding_type_resolution.items[raw] == .unresolved;
    }

    pub fn markBindingTypeUnresolved(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalBindingId) !void {
        const raw: usize = @intFromEnum(id);
        if (raw >= self.bindings.items.len) return error.InvalidGlobalBindingId;
        try self.ensureBindingTypeResolutionCovers(allocator, self.bindings.items.len);
        self.construction.binding_type_resolution.items[raw] = .unresolved;
        self.bindings.items[raw].ty = unresolved_binding_type_poison;
    }

    /// Publish a binding type through the construction-state boundary. New
    /// resolution code should prefer this over patching the binding slot
    /// directly so provisional state is updated at the same time.
    pub fn resolveBindingType(self: *GlobalSemanticGraph, id: GlobalBindingId, ty: GlobalTypeId) !void {
        const raw: usize = @intFromEnum(id);
        if (raw >= self.bindings.items.len) return error.InvalidGlobalBindingId;
        self.bindings.items[raw].ty = ty;
        if (raw < self.construction.binding_type_resolution.items.len)
            self.construction.binding_type_resolution.items[raw] = .resolved;
    }

    pub fn hasUnresolvedBindingTypes(self: *const GlobalSemanticGraph) bool {
        for (self.construction.binding_type_resolution.items) |state| if (state == .unresolved) return true;
        return false;
    }

    pub fn constructionStateEmpty(self: *const GlobalSemanticGraph) bool {
        return self.construction.type_resolution.items.len == 0 and
            self.construction.binding_type_resolution.items.len == 0;
    }

    pub fn finishBindingTypeResolution(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) !void {
        if (self.hasUnresolvedBindingTypes()) return error.UnresolvedGlobalBindingTypes;
        self.construction.binding_type_resolution.deinit(allocator);
        self.construction.binding_type_resolution = .empty;
    }

    fn ensureBindingTypeResolutionCovers(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, count: usize) !void {
        if (self.construction.binding_type_resolution.items.len >= count) return;
        try self.construction.binding_type_resolution.ensureTotalCapacity(allocator, count);
        while (self.construction.binding_type_resolution.items.len < count) self.construction.binding_type_resolution.appendAssumeCapacity(.resolved);
    }

    pub fn node(self: *const GlobalSemanticGraph, id: GlobalNodeId) Node {
        return self.nodes.items[@intFromEnum(id)];
    }

    pub fn moduleNamespace(self: *const GlobalSemanticGraph, id: GlobalModuleId) GlobalModuleId {
        return self.modules.items[@intFromEnum(id)].namespace orelse id;
    }

    pub fn sameModuleNamespace(self: *const GlobalSemanticGraph, left: GlobalModuleId, right: GlobalModuleId) bool {
        if (left == right) return true;
        return self.moduleNamespace(left) == self.moduleNamespace(right);
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
            self.construction.type_resolution.items.len * @sizeOf(TypeResolutionState) +
            self.generic_instances.items.len * @sizeOf(GenericInstance) +
            self.functions.items.len * @sizeOf(Function) +
            self.generic_function_instances.items.len * @sizeOf(GenericFunctionInstance) +
            self.bindings.items.len * @sizeOf(Binding) +
            self.construction.binding_type_resolution.items.len * @sizeOf(TypeResolutionState) +
            self.nodes.items.len * @sizeOf(Node) +
            self.comptime_requests.items.len * @sizeOf(GlobalNodeId) +
            self.blocks.items.len * @sizeOf(Block) +
            self.block_assumptions.items.len * @sizeOf(BlockAssumptions) +
            self.fields.items.len * @sizeOf(Field) +
            self.variants.items.len * @sizeOf(ChoiceVariant) +
            self.generic_arguments.items.len * @sizeOf(GenericArgument) +
            self.argument_defaults.items.len * @sizeOf(ArgumentDefault) +
            self.argument_default_temporaries.items.len * @sizeOf(ArgumentDefaultTemporary) +
            self.argument_default_bindings.items.len * @sizeOf(ArgumentDefaultBinding) +
            self.value_fields.items.len * @sizeOf(ValueField) +
            self.switch_cases.items.len * @sizeOf(SwitchCase) +
            self.switches.items.len * @sizeOf(Switch) +
            self.auto_deinit_fields.items.len * @sizeOf(AutoDeinitField) +
            self.auto_deinits.items.len * @sizeOf(AutoDeinit) +
            self.virtual_registries.items.len * @sizeOf(VirtualMethodRegistry) +
            self.virtualizes.items.len * @sizeOf(Virtualize) +
            self.contract_safety_conformances.items.len * @sizeOf(ContractSafetyConformance) +
            self.contract_conformances.items.len * @sizeOf(ContractConformance) +
            self.contract_operation_bindings.items.len * @sizeOf(ContractOperationBinding) +
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

    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(graph.moduleForSymbol(symbol).?));
    try std.testing.expectEqualStrings("Thing", graph.text(type_name));
}

test "name indexes discard speculative functions before IDs are reused" {
    const allocator = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const first = try graph.addString(allocator, "first");
    const discarded = try graph.addString(allocator, "discarded");
    const replacement = try graph.addString(allocator, "replacement");
    for ([_]StringRange{ first, discarded, replacement }) |name| {
        try graph.declarations.append(allocator, .{
            .kind = .function,
            .name = name,
            .source = .{ .file_index = 0, .offset = 0 },
        });
    }
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
    });
    try std.testing.expectEqual(@as(usize, 1), (try graph.functionsNamed(allocator, "first")).len);
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(1),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
    });
    try std.testing.expectEqual(@as(usize, 1), (try graph.functionsNamed(allocator, "discarded")).len);
    graph.discardIndexedTail(1, 3);
    graph.functions.shrinkRetainingCapacity(1);
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(2),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
    });
    try std.testing.expectEqual(@as(usize, 0), (try graph.functionsNamed(allocator, "discarded")).len);
    try std.testing.expectEqual(@as(usize, 1), (try graph.functionsNamed(allocator, "replacement")).len);
}

test "semantic graph checkpoint restores append-only pools and name indexes" {
    const allocator = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const first = try graph.addString(allocator, "first");
    const discarded = try graph.addString(allocator, "discarded");
    const replacement = try graph.addString(allocator, "replacement");

    try graph.declarations.append(allocator, .{
        .kind = .function,
        .name = first,
        .source = .{ .file_index = 0, .offset = 0 },
    });
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
    });
    _ = try graph.declarationsNamed(allocator, "first");
    _ = try graph.functionsNamed(allocator, "first");

    const saved = graph.checkpoint();
    try graph.declarations.append(allocator, .{
        .kind = .function,
        .name = discarded,
        .source = .{ .file_index = 0, .offset = 0 },
    });
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(1),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
    });
    try graph.nodes.append(allocator, .{
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = null,
        .content = .break_statement,
    });
    try graph.contract_conformances.append(allocator, .{
        .declaration = @enumFromInt(0),
        .participants = .{ .start = 0, .len = 0 },
        .associated_arguments = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
    });
    _ = try graph.declarationsNamed(allocator, "discarded");
    _ = try graph.functionsNamed(allocator, "discarded");

    graph.rollback(saved);
    try std.testing.expectEqual(@as(usize, 1), graph.declarations.items.len);
    try std.testing.expectEqual(@as(usize, 1), graph.functions.items.len);
    try std.testing.expectEqual(@as(usize, 0), graph.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 0), graph.contract_conformances.items.len);
    try std.testing.expectEqual(@as(usize, 0), (try graph.declarationsNamed(allocator, "discarded")).len);
    try std.testing.expectEqual(@as(usize, 0), (try graph.functionsNamed(allocator, "discarded")).len);

    try graph.declarations.append(allocator, .{
        .kind = .function,
        .name = replacement,
        .source = .{ .file_index = 0, .offset = 0 },
    });
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(1),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
    });
    try std.testing.expectEqual(@as(usize, 1), (try graph.declarationsNamed(allocator, "replacement")).len);
    try std.testing.expectEqual(@as(usize, 1), (try graph.functionsNamed(allocator, "replacement")).len);
}

test "unresolved global type slots are construction state, not Any" {
    const allocator = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.markTypeUnresolved(allocator, @enumFromInt(0));
    try std.testing.expect(graph.isTypeUnresolved(@enumFromInt(0)));
    try std.testing.expect(graph.resolvedSemanticType(@enumFromInt(0)) == null);
    try std.testing.expectError(error.UnresolvedGlobalTypeSlots, graph.finishTypeResolution(allocator));

    try graph.resolveType(@enumFromInt(0), .{ .builtin = .Int32 });
    try std.testing.expect(!graph.hasUnresolvedTypes());
    try graph.finishTypeResolution(allocator);
    try std.testing.expect(graph.constructionStateEmpty());
}

test "generic argument rewrites restore existing types across nested checkpoints" {
    const allocator = std.testing.allocator;
    var graph = GlobalSemanticGraph{};
    defer graph.deinit(allocator);
    try graph.generic_arguments.append(allocator, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = @enumFromInt(0) } });
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .generic = .{ .base = @enumFromInt(0), .arguments = .{ .start = 0, .len = 1 } } });
    const outer = graph.checkpoint();
    try graph.generic_arguments.append(allocator, graph.generic_arguments.items[0]);
    try graph.replaceTypeArguments(allocator, @enumFromInt(1), .{ .start = 1, .len = 1 });
    const inner = graph.checkpoint();
    try graph.generic_arguments.append(allocator, graph.generic_arguments.items[0]);
    try graph.replaceTypeArguments(allocator, @enumFromInt(1), .{ .start = 2, .len = 1 });
    graph.rollback(inner);
    try std.testing.expectEqual(@as(u32, 1), graph.types.items[1].generic.arguments.start);
    try std.testing.expectEqual(@as(usize, 2), graph.generic_arguments.items.len);
    graph.rollback(outer);
    try std.testing.expectEqual(@as(u32, 0), graph.types.items[1].generic.arguments.start);
    try std.testing.expectEqual(@as(usize, 1), graph.generic_arguments.items.len);
    try std.testing.expectEqual(@as(usize, 0), graph.construction.type_argument_rewrites.items.len);
}

test "named function lookup excludes instances and callback prototypes across rollback" {
    const allocator = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const name = try graph.addString(allocator, "identity");
    try graph.declarations.append(allocator, .{
        .kind = .function,
        .name = name,
        .source = .{ .file_index = 0, .offset = 0 },
    });
    const callable = Function{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
    };
    try graph.functions.append(allocator, callable);
    const saved = graph.checkpoint();
    var instance = callable;
    instance.flags.is_generic_instantiation = true;
    try graph.functions.append(allocator, instance);
    const callback_name = try graph.addString(allocator, "Callback");
    try graph.declarations.append(allocator, .{
        .kind = .type,
        .name = callback_name,
        .source = .{ .file_index = 0, .offset = 0 },
    });
    var prototype = callable;
    prototype.declaration = @enumFromInt(1);
    prototype.flags.is_c_function_pointer = true;
    try graph.functions.append(allocator, prototype);
    try std.testing.expectEqual(@as(usize, 0), (try graph.functionsNamed(allocator, "Callback")).len);
    const names = try graph.functionsNamed(allocator, "identity");
    try std.testing.expectEqual(@as(usize, 1), names.len);
    try std.testing.expectEqual(@as(GlobalFunctionId, @enumFromInt(0)), names[0]);
    // Cached bodies remain addressable for codegen, without joining name lookup.
    try std.testing.expect(graph.function(@enumFromInt(1)).flags.is_generic_instantiation);
    try std.testing.expect(graph.function(@enumFromInt(2)).flags.is_c_function_pointer);
    graph.rollback(saved);
    try graph.functions.append(allocator, callable);
    try std.testing.expectEqual(@as(usize, 2), (try graph.functionsNamed(allocator, "identity")).len);
}

test "selected call evidence stays compact and distinguishes aliased operations" {
    var graph: GlobalSemanticGraph = .{};
    // Keep the shared node union within its compact representation budget.
    try std.testing.expect(@sizeOf(Node) <= 112);
    const ordinary = Node.Content{ .function_call = .{ .callee = @enumFromInt(0), .input = @enumFromInt(0) } };
    try std.testing.expect(graph.callOperation(ordinary.function_call) == null);
    var first = ordinary.function_call;
    first.contract_operation = .{ .conformance = 3, .index = 2 };
    var second = first;
    second.contract_operation = .{ .conformance = 5, .index = 1 };
    try std.testing.expectEqual(first.callee, second.callee);
    try std.testing.expectEqual(@as(u32, 3), graph.callOperation(first).?.conformance);
    try std.testing.expectEqual(@as(u32, 2), graph.callOperation(first).?.index);
    try std.testing.expectEqual(@as(u32, 5), graph.callOperation(second).?.conformance);
    try std.testing.expectEqual(@as(u32, 1), graph.callOperation(second).?.index);
}

test "parameterized function index extends retained module prefixes" {
    const a = std.testing.allocator;
    var first: module_sg.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "first") };
    defer first.deinit(a);
    var second: module_sg.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "second") };
    defer second.deinit(a);
    for ([_]*module_sg.ModuleSemanticGraph{ &first, &second }) |module| {
        try module.strings.appendSlice(a, "work");
        try module.declarations.append(a, .{ .kind = .function, .name = .{ .start = 0, .len = 4 }, .source_offset = 0, .module_file_index = 0 });
        try module.semantic.parameterized_storage.parameterized_functions.append(a, .{
            .declaration = @enumFromInt(0),
            .parameters = .{ .start = 0, .len = 0 },
            .input = @enumFromInt(0),
            .output = @enumFromInt(0),
            .body = null,
        });
    }
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const modules = [_]module_sg.ModuleSemanticGraph{ first, second };
    try std.testing.expectEqual(@as(usize, 1), (try graph.parameterizedFunctionsNamed(a, modules[0..1], "work")).len);
    const candidates = try graph.parameterizedFunctionsNamed(a, &modules, "work");
    try std.testing.expectEqual(@as(usize, 2), candidates.len);
    try std.testing.expectEqual(@as(u32, 0), candidates[0].module_index);
    try std.testing.expectEqual(@as(u32, 1), candidates[1].module_index);
    try std.testing.expectEqual(@as(usize, 2), (try graph.parameterizedFunctionsNamed(a, &modules, "work")).len);

    // Grow the shared spelling's candidate list through several allocations.
    // An interrupted extension must resume at the next unpublished template.
    const template = second.semantic.parameterized_storage.parameterized_functions.items[0];
    try second.semantic.parameterized_storage.parameterized_functions.appendNTimes(a, template, 31);
    const extended = [_]module_sg.ModuleSemanticGraph{ first, second };
    for (0..6) |failure_index| {
        var retry: GlobalSemanticGraph = .{};
        defer retry.deinit(a);
        _ = try retry.parameterizedFunctionsNamed(a, extended[0..1], "work");
        var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = failure_index });
        _ = retry.parameterizedFunctionsNamed(failing.allocator(), &extended, "work") catch |err| switch (err) {
            error.OutOfMemory => &.{},
        };
        const resumed = try retry.parameterizedFunctionsNamed(a, &extended, "work");
        try std.testing.expectEqual(@as(usize, 33), resumed.len);
        for (resumed[1..], 0..) |candidate, index| {
            try std.testing.expectEqual(@as(u32, 1), candidate.module_index);
            try std.testing.expectEqual(@as(u32, @intCast(index)), candidate.function_index);
        }
    }
}

fn cloneConstructionGraph(allocator: std.mem.Allocator) !void {
    const source_allocator = std.testing.allocator;
    var source: GlobalSemanticGraph = .{};
    defer source.deinit(source_allocator);
    const name = try source.addString(source_allocator, "retained");
    try source.declarations.append(source_allocator, .{ .kind = .function, .name = name, .source = .{ .file_index = 0, .offset = 0 } });
    try source.functions.append(source_allocator, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } });
    try source.types.appendSlice(source_allocator, &.{ .{ .builtin = .Any }, .{ .builtin = .Int32 } });
    try source.markTypeUnresolved(source_allocator, @enumFromInt(0));
    _ = try source.functionsNamed(source_allocator, "retained");
    _ = try source.declarationsNamed(source_allocator, "retained");
    const saved = source.checkpoint();
    var copy = try source.clone(allocator);
    defer copy.deinit(allocator);
    try std.testing.expect(copy.isTypeUnresolved(@enumFromInt(0)));
    try copy.resolveType(@enumFromInt(0), .{ .builtin = .UInt8 });
    copy.types.items[1] = .{ .builtin = .Int64 };
    copy.functions.items[0].flags.is_c_export = true;
    try std.testing.expect(source.isTypeUnresolved(@enumFromInt(0)));
    try std.testing.expectEqual(primitives.BuiltinType.Int32, source.types.items[1].builtin);
    try std.testing.expect(!source.functions.items[0].flags.is_c_export);
    try std.testing.expectEqual(@as(usize, 1), (try copy.functionsNamed(allocator, "retained")).len);
    try std.testing.expectEqual(@as(usize, 1), (try copy.declarationsNamed(allocator, "retained")).len);
    const added_name = try copy.addString(allocator, "submission");
    try copy.declarations.append(allocator, .{ .kind = .function, .name = added_name, .source = .{ .file_index = 0, .offset = 0 } });
    try copy.functions.append(allocator, .{ .declaration = @enumFromInt(1), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } });
    try std.testing.expectEqual(@as(usize, 1), (try copy.functionsNamed(allocator, "submission")).len);
    try std.testing.expectEqual(@as(usize, 0), (try source.functionsNamed(source_allocator, "submission")).len);
    try std.testing.expectEqualDeep(saved, source.checkpoint());
}

test "semantic graph clones isolate in-place edits and preserve construction identities" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneConstructionGraph, .{});
}

fn cloneSafetySelectors(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    var source: GlobalSemanticGraph = .{};
    defer source.deinit(a);
    const arena = try source.safetyAllocator(a);
    const location: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    const outcomes = try arena.alloc(primitives.MethodSafetyContract.Outcome, 1);
    outcomes[0] = .{ .variant = .{ .start = 0, .len = 0 }, .parent_variants = try arena.dupe(u32, &.{3}), .source = location };
    try source.contract_safety_conformances.append(a, .{
        .selection = .{ .conformance = 0, .index = 0 },
        .method = @enumFromInt(0),
        .contract = .{ .output_count = 1, .outcomes = outcomes, .source = location },
        .receiver_input_index = null,
        .source = location,
    });
    var copy = try source.clone(allocator);
    defer copy.deinit(allocator);
    source.deinit(a);
    try std.testing.expectEqual(@as(u32, 3), copy.contract_safety_conformances.items[0].contract.outcomes[0].parent_variants[0]);
}

test "semantic graph safety selectors survive source destruction and failed cloning" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneSafetySelectors, .{});
}

test "snapshot capacity trimming preserves pool pointers and identities" {
    const a = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.ensureTotalCapacity(a, 100);
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.strings.appendSlice(a, "retained");
    const type_pointer = graph.types.items.ptr;
    const text_pointer = graph.strings.items.ptr;
    const capacity = graph.types.capacity;
    graph.trimPoolCapacity(a);
    try std.testing.expectEqual(type_pointer, graph.types.items.ptr);
    try std.testing.expectEqual(text_pointer, graph.strings.items.ptr);
    try std.testing.expect(graph.types.capacity <= capacity);
    try std.testing.expectEqual(primitives.BuiltinType.Int32, graph.types.items[0].builtin);
    try std.testing.expectEqualStrings("retained", graph.strings.items);
    // A second trim is harmless, including empty graph columns.
    graph.trimPoolCapacity(a);
}
