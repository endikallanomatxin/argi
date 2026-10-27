const std = @import("std");
const primitives = @import("../primitives/schema.zig");
const semantic_strings = @import("../primitives/strings.zig");
const type_shapes = @import("../primitives/type_shapes.zig");
const module_sg = @import("../module/graph.zig");

pub const GlobalDeclId = enum(u32) { _ };
pub const GlobalTypeId = enum(u32) { _ };
pub const GlobalTypeDefinitionId = enum(u32) { _ };
pub const GlobalFamilyDefinitionId = enum(u32) { _ };
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
    pub const TypeDefinitionId = GlobalTypeDefinitionId;
    pub const FamilyDefinitionId = GlobalFamilyDefinitionId;
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
pub const TypeDefinition = primitives.TypeDefinition(Ids);
pub const FamilyDefinition = primitives.FamilyDefinition(Ids);
pub const DefinitionValue = primitives.DefinitionValue(Ids);
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
    contract_definition: GlobalFamilyDefinitionId,
    requirement_index: u32,
    requirement_source: primitives.SourceRef,
    implementation_source: primitives.SourceRef,
    alias_source: ?primitives.SourceRef = null,
    name: StringRange,
    // The ordinary compile-time expression retains aliases and deferred
    // specialization captures without a second resolution mechanism.
    definition: GlobalNodeId,
    instantiate_associated: bool = false,
    materialized_function: ?GlobalFunctionId = null,
};
pub const ContractConformance = struct {
    // Declaration/signature validation is separate from the later safety proof.
    declaration_validated: bool = false,
    implementation_arguments: primitives.Range(GlobalGenericArgId) = .{ .start = 0, .len = 0 },
    operation_bindings: primitives.Range(ContractOperationBindingId) = .{ .start = 0, .len = 0 },
    context: GlobalModuleId = @enumFromInt(0),
    declaration: GlobalFamilyDefinitionId,
    participants: primitives.Range(GlobalGenericArgId),
    associated_arguments: primitives.Range(GlobalGenericArgId),
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
    parameterized_definition: GlobalFamilyDefinitionId,
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

pub const unresolved_type_poison_definition: GlobalTypeDefinitionId = @enumFromInt(std.math.maxInt(u32));
const unresolved_binding_type_poison: GlobalTypeId = @enumFromInt(std.math.maxInt(u32));

pub const ArgumentDefaultTemporary = struct { expression: GlobalNodeId, declaration: GlobalNodeId };
pub const CapturedExpressionBinding = struct { ty: ?GlobalTypeId, integer: ?i64, definition: ?DefinitionValue = null };
pub const CapturedExpression = struct {
    module_index: usize,
    expression: @import("../module/parameterized/ir.zig").ParameterizedNodeId,
    bindings: primitives.Range(u32),
};

pub const GlobalSemanticGraph = struct {
    pub const Checkpoint = struct {
        pool_lengths: [@typeInfo(GlobalSemanticGraph).@"struct".fields.len]usize,
        indexed_functions: usize,
        indexed_declarations: usize,
        indexed_parameterized_modules: usize,
        indexed_module_functions: usize,
        type_resolution_len: usize,
        binding_type_resolution_len: usize,
        type_rewrites_len: usize,
        binding_rewrites_len: usize,
        function_rewrites_len: usize,
        virtual_completions_len: usize,
        node_rewrites_len: usize,
        block_rewrites_len: usize,
        error_context_rewrites_len: usize,
        conformance_rewrites_len: usize,
        operation_completions_len: usize,
        variant_rewrites_len: usize,
        definition_rewrites_len: usize,
        error_propagation_rewrites_len: usize,
        safety_arena: ?*std.heap.ArenaAllocator,
    };

    const MutationFrontier = struct {
        types: usize,
        type_definitions: usize,
        bindings: usize,
        virtual_registries: usize,
        nodes: usize,
        blocks: usize,
        error_propagations: usize,
        error_contexts: usize,
        contract_conformances: usize,
        contract_operation_bindings: usize,
        variants: usize,
        functions: usize,
        depth: usize,
    };

    /// Coordinates pool tails and journals for older semantic slots. Resolver
    /// worklists and caches still require the enclosing side-effect checkpoint.
    pub const Transaction = struct {
        graph: *GlobalSemanticGraph,
        allocator: std.mem.Allocator,
        saved: Checkpoint,
        parent: ?MutationFrontier,
        frontier: MutationFrontier,
        active: bool = true,

        pub fn commit(self: *Transaction) void {
            if (!self.active) return;
            std.debug.assert(std.meta.eql(self.graph.mutation_frontier.?, self.frontier));
            self.graph.mutation_frontier = self.parent;
            self.graph.safety_arena = self.saved.safety_arena;
            self.active = false;
        }

        pub fn rollback(self: *Transaction) void {
            if (!self.active) return;
            std.debug.assert(std.meta.eql(self.graph.mutation_frontier.?, self.frontier));
            self.graph.rollback(self.allocator, self.saved);
            self.graph.mutation_frontier = self.parent;
            self.active = false;
        }

        pub fn deinit(self: *Transaction) void {
            self.rollback();
        }
    };

    pub fn beginTransaction(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) Transaction {
        const parent = self.mutation_frontier;
        const frontier: MutationFrontier = .{
            .types = self.types.items.len,
            .type_definitions = self.type_definitions.items.len,
            .bindings = self.bindings.items.len,
            .virtual_registries = self.virtual_registries.items.len,
            .nodes = self.nodes.items.len,
            .blocks = self.blocks.items.len,
            .error_propagations = self.error_propagations.items.len,
            .error_contexts = self.error_contexts.items.len,
            .contract_conformances = self.contract_conformances.items.len,
            .contract_operation_bindings = self.contract_operation_bindings.items.len,
            .variants = self.variants.items.len,
            .functions = self.functions.items.len,
            .depth = if (parent) |value| value.depth + 1 else 1,
        };
        const saved = self.checkpoint();
        self.mutation_frontier = frontier;
        // New immutable metadata belongs to this scope. A child never appends
        // to an older arena that its rollback would be unable to reclaim.
        self.safety_arena = null;
        return .{ .graph = self, .allocator = allocator, .saved = saved, .parent = parent, .frontier = frontier };
    }

    pub const BindingInitialization = struct {
        binding: GlobalBindingId,
        value: GlobalNodeId,
    };

    const ConstructionState = struct {
        function_rewrites: std.ArrayList(struct { id: GlobalFunctionId, previous: Function }) = .empty,
        error_propagation_rewrites: std.ArrayList(struct { id: GlobalErrorPropagationId, previous: ErrorPropagation }) = .empty,
        definition_rewrites: std.ArrayList(struct { id: GlobalTypeDefinitionId, previous: TypeDefinition }) = .empty,
        variant_rewrites: std.ArrayList(struct { id: GlobalVariantId, previous: ChoiceVariant }) = .empty,
        operation_completions: std.ArrayList(struct { id: ContractOperationBindingId, previous: ?GlobalFunctionId }) = .empty,
        conformance_rewrites: std.ArrayList(struct { index: u32, previous: ContractConformance }) = .empty,
        error_context_rewrites: std.ArrayList(struct { id: GlobalErrorContextId, previous: ErrorContext }) = .empty,
        block_rewrites: std.ArrayList(struct { id: GlobalBlockId, previous: Block }) = .empty,
        node_rewrites: std.ArrayList(struct { id: GlobalNodeId, previous: Node }) = .empty,
        virtual_completions: std.ArrayList(struct { id: GlobalVirtualRegistryId, previous: VirtualMethodRegistry }) = .empty,
        type_resolution: std.ArrayList(TypeResolutionState) = .empty,
        binding_type_resolution: std.ArrayList(TypeResolutionState) = .empty,
        type_rewrites: std.ArrayList(struct {
            type_id: GlobalTypeId,
            previous: GlobalType,
            resolution: TypeResolutionState,
        }) = .empty,
        binding_rewrites: std.ArrayList(struct {
            binding_id: GlobalBindingId,
            previous: Binding,
            resolution: TypeResolutionState,
        }) = .empty,

        fn deinit(self: *ConstructionState, allocator: std.mem.Allocator) void {
            self.function_rewrites.deinit(allocator);
            self.virtual_completions.deinit(allocator);
            self.node_rewrites.deinit(allocator);
            self.block_rewrites.deinit(allocator);
            self.error_context_rewrites.deinit(allocator);
            self.conformance_rewrites.deinit(allocator);
            self.operation_completions.deinit(allocator);
            self.definition_rewrites.deinit(allocator);
            self.variant_rewrites.deinit(allocator);
            self.error_propagation_rewrites.deinit(allocator);
            self.type_resolution.deinit(allocator);
            self.binding_type_resolution.deinit(allocator);
            self.type_rewrites.deinit(allocator);
            self.binding_rewrites.deinit(allocator);
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
    type_definitions: std.ArrayList(TypeDefinition) = .empty,
    family_definitions: std.ArrayList(FamilyDefinition) = .empty,
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
    captured_expressions: std.ArrayList(CapturedExpression) = .empty,
    argument_default_temporaries: std.ArrayList(ArgumentDefaultTemporary) = .empty,
    captured_expression_bindings: std.ArrayList(CapturedExpressionBinding) = .empty,
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

    // Immutable metadata is owned in transaction batches. The current arena
    // is only an allocation cursor; committed child batches remain owned here.
    safety_arena: ?*std.heap.ArenaAllocator = null,
    safety_batches: std.ArrayList(*std.heap.ArenaAllocator) = .empty,

    // Transient lookup state used while building/querying GlobalSema. The
    // append-only semantic pools remain the source of truth; these indexes are
    // derived state and are not part of a persistent semantic representation.
    lookup: LookupState = .{},

    // Pending-slot metadata is separate from language types. A selected unit
    // must resolve every binding it uses; dormant bodies may retain holes.
    construction: ConstructionState = .{},
    mutation_frontier: ?MutationFrontier = null,

    pub fn safetyAllocator(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) !std.mem.Allocator {
        if (self.safety_arena == null) {
            const arena = try allocator.create(std.heap.ArenaAllocator);
            errdefer allocator.destroy(arena);
            arena.* = .init(allocator);
            try self.safety_batches.append(allocator, arena);
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

    fn copyStorageDomains(allocator: std.mem.Allocator, source: []const primitives.StorageDomainMapping) ![]const primitives.StorageDomainMapping {
        const result = try allocator.dupe(primitives.StorageDomainMapping, source);
        for (result) |*mapping| {
            const paths = try allocator.dupe(primitives.StorageDomainMapping.Path, mapping.paths);
            for (paths) |*path| path.fields = try allocator.dupe(u32, path.fields);
            mapping.paths = paths;
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
            if (comptime std.mem.eql(u8, field.name, "safety_batches")) continue;
            if (comptime switch (@typeInfo(field.type)) {
                .@"struct" => @hasField(field.type, "items"),
                else => false,
            }) try @field(result, field.name).appendSlice(allocator, @field(self, field.name).items);
        }
        for (result.virtual_registries.items) |*registry| if (registry.safety_contract) |*contract| {
            contract.outcomes = try copySafetyOutcomes(try result.safetyAllocator(allocator), contract.outcomes);
        };
        for (result.contract_safety_conformances.items) |*conformance| {
            const arena = try result.safetyAllocator(allocator);
            conformance.contract.outcomes = try copySafetyOutcomes(arena, conformance.contract.outcomes);
            conformance.domains = try copyStorageDomains(arena, conformance.domains);
        }
        for (result.virtualizes.items) |*value| {
            value.domains = try copyStorageDomains(try result.safetyAllocator(allocator), value.domains);
        }
        inline for (@typeInfo(ConstructionState).@"struct".fields) |field| {
            try @field(result.construction, field.name).appendSlice(allocator, @field(self.construction, field.name).items);
        }
        for (result.construction.virtual_completions.items) |*entry| if (entry.previous.safety_contract) |*contract| {
            contract.outcomes = try copySafetyOutcomes(try result.safetyAllocator(allocator), contract.outcomes);
        };
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
            .pool_lengths = @splat(0),
            .indexed_functions = self.lookup.indexed_functions,
            .indexed_declarations = self.lookup.indexed_declarations,
            .indexed_parameterized_modules = self.lookup.indexed_parameterized_modules,
            .indexed_module_functions = self.lookup.indexed_module_functions,
            .type_resolution_len = self.construction.type_resolution.items.len,
            .binding_type_resolution_len = self.construction.binding_type_resolution.items.len,
            .type_rewrites_len = self.construction.type_rewrites.items.len,
            .binding_rewrites_len = self.construction.binding_rewrites.items.len,
            .function_rewrites_len = self.construction.function_rewrites.items.len,
            .virtual_completions_len = self.construction.virtual_completions.items.len,
            .node_rewrites_len = self.construction.node_rewrites.items.len,
            .block_rewrites_len = self.construction.block_rewrites.items.len,
            .error_context_rewrites_len = self.construction.error_context_rewrites.items.len,
            .conformance_rewrites_len = self.construction.conformance_rewrites.items.len,
            .operation_completions_len = self.construction.operation_completions.items.len,
            .variant_rewrites_len = self.construction.variant_rewrites.items.len,
            .definition_rewrites_len = self.construction.definition_rewrites.items.len,
            .error_propagation_rewrites_len = self.construction.error_propagation_rewrites.items.len,
            .safety_arena = self.safety_arena,
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
    /// Type rewrites restore payloads and resolution flags in write order,
    /// including canonical arguments. Binding types and function completions
    /// are restored before their referenced pools shrink.
    /// Resolver-owned worklists and caches remain outside this graph checkpoint.
    pub fn rollback(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, saved: Checkpoint) void {
        const pools = @typeInfo(GlobalSemanticGraph).@"struct".fields;
        self.discardIndexedTail(allocator, saved.indexed_functions, saved.indexed_declarations);
        self.discardParameterizedTail(allocator, saved.indexed_parameterized_modules, saved.indexed_module_functions);
        while (self.construction.node_rewrites.items.len > saved.node_rewrites_len) {
            const rewrite = self.construction.node_rewrites.pop().?;
            self.nodes.items[@intFromEnum(rewrite.id)] = rewrite.previous;
        }
        while (self.construction.virtual_completions.items.len > saved.virtual_completions_len) {
            const previous = self.construction.virtual_completions.pop().?;
            self.virtual_registries.items[@intFromEnum(previous.id)] = previous.previous;
        }
        while (self.construction.function_rewrites.items.len > saved.function_rewrites_len) {
            const rewrite = self.construction.function_rewrites.pop().?;
            self.functions.items[@intFromEnum(rewrite.id)] = rewrite.previous;
        }
        while (self.construction.error_propagation_rewrites.items.len > saved.error_propagation_rewrites_len) {
            const rewrite = self.construction.error_propagation_rewrites.pop().?;
            self.error_propagations.items[@intFromEnum(rewrite.id)] = rewrite.previous;
        }
        while (self.construction.definition_rewrites.items.len > saved.definition_rewrites_len) {
            const rewrite = self.construction.definition_rewrites.pop().?;
            self.type_definitions.items[@intFromEnum(rewrite.id)] = rewrite.previous;
        }
        while (self.construction.variant_rewrites.items.len > saved.variant_rewrites_len) {
            const rewrite = self.construction.variant_rewrites.pop().?;
            self.variants.items[@intFromEnum(rewrite.id)] = rewrite.previous;
        }
        while (self.construction.operation_completions.items.len > saved.operation_completions_len) {
            const completion = self.construction.operation_completions.pop().?;
            self.contract_operation_bindings.items[@intFromEnum(completion.id)].materialized_function = completion.previous;
        }
        while (self.construction.conformance_rewrites.items.len > saved.conformance_rewrites_len) {
            const rewrite = self.construction.conformance_rewrites.pop().?;
            self.contract_conformances.items[rewrite.index] = rewrite.previous;
        }
        while (self.construction.error_context_rewrites.items.len > saved.error_context_rewrites_len) {
            const rewrite = self.construction.error_context_rewrites.pop().?;
            self.error_contexts.items[@intFromEnum(rewrite.id)] = rewrite.previous;
        }
        while (self.construction.block_rewrites.items.len > saved.block_rewrites_len) {
            const rewrite = self.construction.block_rewrites.pop().?;
            self.blocks.items[@intFromEnum(rewrite.id)] = rewrite.previous;
        }
        while (self.construction.type_rewrites.items.len > saved.type_rewrites_len) {
            const rewrite = self.construction.type_rewrites.pop().?;
            const raw = @intFromEnum(rewrite.type_id);
            self.types.items[raw] = rewrite.previous;
            if (raw < self.construction.type_resolution.items.len)
                self.construction.type_resolution.items[raw] = rewrite.resolution;
        }
        while (self.construction.binding_rewrites.items.len > saved.binding_rewrites_len) {
            const rewrite = self.construction.binding_rewrites.pop().?;
            const raw = @intFromEnum(rewrite.binding_id);
            self.bindings.items[raw] = rewrite.previous;
            if (raw < self.construction.binding_type_resolution.items.len)
                self.construction.binding_type_resolution.items[raw] = rewrite.resolution;
        }
        self.construction.type_resolution.shrinkRetainingCapacity(saved.type_resolution_len);
        self.construction.binding_type_resolution.shrinkRetainingCapacity(saved.binding_type_resolution_len);
        inline for (pools, 0..) |pool, index| {
            if (comptime std.mem.eql(u8, pool.name, "safety_batches")) continue;
            if (comptime switch (@typeInfo(pool.type)) {
                .@"struct" => @hasField(pool.type, "items"),
                else => false,
            }) {
                @field(self, pool.name).shrinkRetainingCapacity(saved.pool_lengths[index]);
            }
        }
        const batch_count = saved.pool_lengths[std.meta.fieldIndex(GlobalSemanticGraph, "safety_batches").?];
        for (self.safety_batches.items[batch_count..]) |arena| {
            arena.deinit();
            allocator.destroy(arena);
        }
        self.safety_batches.shrinkRetainingCapacity(batch_count);
        self.safety_arena = saved.safety_arena;
    }

    pub fn deinit(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) void {
        self.lookup.deinit(allocator);
        self.construction.deinit(allocator);
        for (self.safety_batches.items) |arena| {
            arena.deinit();
            allocator.destroy(arena);
        }
        self.safety_batches.deinit(allocator);
        inline for (.{
            &self.modules,                      &self.module_aliases,               &self.files,                       &self.declarations,
            &self.symbols,                      &self.symbol_declarations,          &self.types,                       &self.type_definitions,
            &self.family_definitions,           &self.generic_instances,            &self.functions,                   &self.generic_function_instances,
            &self.bindings,                     &self.nodes,                        &self.blocks,                      &self.fields,
            &self.variants,                     &self.generic_arguments,            &self.value_fields,                &self.switch_cases,
            &self.switches,                     &self.auto_deinit_fields,           &self.auto_deinits,                &self.virtual_registries,
            &self.virtualizes,                  &self.virtual_calls,                &self.reach_segments,              &self.reach_alternatives,
            &self.reaches,                      &self.nullable_unwraps,             &self.testing_expect_errors,       &self.error_propagations,
            &self.error_contexts,               &self.node_refs,                    &self.type_refs,                   &self.binding_refs,
            &self.function_refs,                &self.virtual_registry_refs,        &self.strings,                     &self.roots,
            &self.contract_safety_conformances, &self.contract_conformances,        &self.contract_operation_bindings, &self.captured_expressions,
            &self.argument_default_temporaries, &self.captured_expression_bindings, &self.comptime_requests,           &self.block_assumptions,
        }) |list| list.deinit(allocator);
        self.* = .{};
    }

    pub fn declarationSourceName(self: *const GlobalSemanticGraph, id: GlobalDeclId) StringRange {
        for (self.contract_operation_bindings.items) |operation_binding| {
            const definition = @import("types.zig").definitionValue(self, operation_binding.definition) orelse continue;
            if (operation_binding.instantiate_associated and self.familyDeclaration(definition.origin) == id) return operation_binding.name;
        }
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
            try appendNamed(GlobalFunctionId, allocator, &self.lookup.function_names, spelling, @enumFromInt(raw));

            self.lookup.indexed_functions += 1;
        }
        return if (self.lookup.function_names.get(name)) |matches| matches.items else &.{};
    }

    pub fn declarationsNamed(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, name: []const u8) ![]const GlobalDeclId {
        while (self.lookup.indexed_declarations < self.declarations.items.len) {
            const raw = self.lookup.indexed_declarations;
            const spelling = self.text(self.declarations.items[raw].name);
            try appendNamed(GlobalDeclId, allocator, &self.lookup.declaration_names, spelling, @enumFromInt(raw));
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
    pub fn discardIndexedTail(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, function_count: usize, declaration_count: usize) void {
        while (self.lookup.indexed_functions > function_count) {
            self.lookup.indexed_functions -= 1;
            const entry = self.functions.items[self.lookup.indexed_functions];
            if (!isNamedFunction(entry)) continue;
            const name = self.text(self.declarations.items[@intFromEnum(entry.declaration)].name);
            popNamed(GlobalFunctionId, allocator, &self.lookup.function_names, name);
        }
        while (self.lookup.indexed_declarations > declaration_count) {
            self.lookup.indexed_declarations -= 1;
            const name = self.text(self.declarations.items[self.lookup.indexed_declarations].name);
            popNamed(GlobalDeclId, allocator, &self.lookup.declaration_names, name);
        }
    }

    fn appendNamed(comptime T: type, allocator: std.mem.Allocator, map: *std.StringHashMapUnmanaged(std.ArrayList(T)), name: []const u8, value: T) !void {
        if (map.getPtr(name)) |items| return items.append(allocator, value);
        const owned = try allocator.dupe(u8, name);
        errdefer allocator.free(owned);
        var items: std.ArrayList(T) = .empty;
        errdefer items.deinit(allocator);
        try items.append(allocator, value);
        try map.put(allocator, owned, items);
    }

    fn popNamed(comptime T: type, allocator: std.mem.Allocator, map: *std.StringHashMapUnmanaged(std.ArrayList(T)), name: []const u8) void {
        const items = map.getPtr(name).?;
        _ = items.pop().?;
        if (items.items.len != 0) return;
        var removed = map.fetchRemove(name).?;
        removed.value.deinit(allocator);
        allocator.free(removed.key);
    }

    fn discardParameterizedTail(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, module_count: usize, function_count: usize) void {
        if (self.lookup.indexed_parameterized_modules == module_count and self.lookup.indexed_module_functions == function_count) return;
        var entries = self.lookup.parameterized_function_names.iterator();
        while (entries.next()) |entry| {
            const items = entry.value_ptr;
            while (items.items.len != 0) {
                const last = items.items[items.items.len - 1];
                if (last.module_index < module_count or (last.module_index == module_count and last.function_index < function_count)) break;
                _ = items.pop();
            }
            if (items.items.len == 0) {
                const key = entry.key_ptr.*;
                items.deinit(allocator);
                // Removing the current slot does not move or rehash the table.
                self.lookup.parameterized_function_names.removeByPtr(entry.key_ptr);
                allocator.free(key);
            }
        }
        self.lookup.indexed_parameterized_modules = module_count;
        self.lookup.indexed_module_functions = function_count;
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
                try appendNamed(ParameterizedFunctionCandidate, allocator, &self.lookup.parameterized_function_names, spelling, .{
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

    pub fn familyDefinition(self: *const GlobalSemanticGraph, id: GlobalFamilyDefinitionId) FamilyDefinition {
        return self.family_definitions.items[@intFromEnum(id)];
    }

    pub fn familyDeclaration(self: *const GlobalSemanticGraph, id: GlobalFamilyDefinitionId) GlobalDeclId {
        return self.familyDefinition(id).declaration.?;
    }

    pub fn familyForDeclaration(self: *const GlobalSemanticGraph, id: GlobalDeclId) ?GlobalFamilyDefinitionId {
        return self.declaration(id).family_definition;
    }

    pub fn familyDefinitionName(self: *const GlobalSemanticGraph, id: GlobalFamilyDefinitionId) []const u8 {
        return if (self.familyDefinition(id).declaration) |declaration_id| self.text(self.declaration(declaration_id).name) else "<anonymous>";
    }

    pub fn moduleForFamilyDefinition(self: *const GlobalSemanticGraph, id: GlobalFamilyDefinitionId) ?GlobalModuleId {
        return self.moduleForPartition("files", self.familyDefinition(id).source.file_index);
    }

    pub fn typeDefinitionName(self: *const GlobalSemanticGraph, id: GlobalTypeDefinitionId) []const u8 {
        const definition = self.typeDefinition(id);
        return if (definition.declaration) |declaration_id| self.text(self.declaration(declaration_id).name) else "<anonymous>";
    }

    pub fn typeDefinition(self: *const GlobalSemanticGraph, id: GlobalTypeDefinitionId) TypeDefinition {
        return self.type_definitions.items[@intFromEnum(id)];
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
        try self.recordTypeRewrite(allocator, id, false);
        try self.ensureTypeResolutionCovers(allocator, self.types.items.len);
        self.construction.type_resolution.items[raw] = .unresolved;
        self.types.items[raw] = .{ .nominal = unresolved_type_poison_definition };
    }

    /// Publish a type through the construction-state boundary. Type holes must
    /// be resolved through this API so GlobalSema never needs to rediscover
    /// direct slot writes with a full-pool reconciliation scan.
    pub fn resolveType(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalTypeId, value: GlobalType) !void {
        const raw: usize = @intFromEnum(id);
        if (raw >= self.types.items.len) return error.InvalidGlobalTypeId;
        try self.recordTypeRewrite(allocator, id, false);
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
        try self.recordTypeRewrite(allocator, id, true);
        self.types.items[raw].generic.arguments = arguments;
    }

    fn recordTypeRewrite(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalTypeId, canonical_arguments: bool) !void {
        const raw = @intFromEnum(id);
        if (!canonical_arguments) {
            const frontier = self.mutation_frontier orelse return;
            if (raw >= frontier.types) return;
        }
        try self.construction.type_rewrites.append(allocator, .{
            .type_id = id,
            .previous = self.types.items[raw],
            .resolution = if (self.isTypeUnresolved(id)) .unresolved else .resolved,
        });
    }

    fn recordBindingRewrite(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalBindingId) !void {
        const frontier = self.mutation_frontier orelse return;
        const raw = @intFromEnum(id);
        if (raw >= frontier.bindings) return;
        try self.construction.binding_rewrites.append(allocator, .{
            .binding_id = id,
            .previous = self.bindings.items[raw],
            .resolution = if (self.isBindingTypeUnresolved(id)) .unresolved else .resolved,
        });
    }

    pub fn hasUnresolvedTypes(self: *const GlobalSemanticGraph) bool {
        for (self.construction.type_resolution.items) |state| if (state == .unresolved) return true;
        return false;
    }

    /// Release completed type-resolution bookkeeping. This does not change
    /// semantic type identities or stand in for selected-unit verification.
    pub fn finishTypeResolution(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) !void {
        if (self.hasUnresolvedTypes()) return error.UnresolvedGlobalTypeSlots;
        self.construction.type_resolution.deinit(allocator);
        self.construction.type_resolution = .empty;
    }

    /// A successful outer publication no longer needs completion undo entries.
    /// This invalidates checkpoints taken before publication.
    pub fn commitCompletions(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) void {
        std.debug.assert(self.mutation_frontier == null);
        self.construction.type_rewrites.deinit(allocator);
        self.construction.type_rewrites = .empty;
        self.construction.binding_rewrites.deinit(allocator);
        self.construction.binding_rewrites = .empty;
        self.construction.function_rewrites.deinit(allocator);
        self.construction.function_rewrites = .empty;
        self.construction.virtual_completions.deinit(allocator);
        self.construction.virtual_completions = .empty;
        self.construction.node_rewrites.deinit(allocator);
        self.construction.node_rewrites = .empty;
        self.construction.block_rewrites.deinit(allocator);
        self.construction.block_rewrites = .empty;
        self.construction.error_context_rewrites.deinit(allocator);
        self.construction.error_context_rewrites = .empty;
        self.construction.conformance_rewrites.deinit(allocator);
        self.construction.conformance_rewrites = .empty;
        self.construction.operation_completions.deinit(allocator);
        self.construction.operation_completions = .empty;
        self.construction.definition_rewrites.deinit(allocator);
        self.construction.definition_rewrites = .empty;
        self.construction.variant_rewrites.deinit(allocator);
        self.construction.variant_rewrites = .empty;
        self.construction.error_propagation_rewrites.deinit(allocator);
        self.construction.error_propagation_rewrites = .empty;
    }

    fn ensureTypeResolutionCovers(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, count: usize) !void {
        if (self.construction.type_resolution.items.len >= count) return;
        try self.construction.type_resolution.ensureTotalCapacity(allocator, count);
        while (self.construction.type_resolution.items.len < count) self.construction.type_resolution.appendAssumeCapacity(.resolved);
    }

    /// Complete a published signature once. Reserve the entire undo journal
    /// before changing older slots so allocation failure leaves them intact.
    /// IDs, not pool element pointers, survive growth and nested speculation.
    pub fn completeFunctionBody(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalFunctionId, body: GlobalBlockId, defaults: []const BindingInitialization) !void {
        const raw = @intFromEnum(id);
        if (raw >= self.functions.items.len or @intFromEnum(body) >= self.blocks.items.len) return error.InvalidFunctionCompletion;
        if (self.functions.items[raw].body != null) return error.FunctionBodyAlreadyCompleted;
        for (defaults) |entry| {
            if (@intFromEnum(entry.binding) >= self.bindings.items.len or @intFromEnum(entry.value) >= self.nodes.items.len)
                return error.InvalidFunctionCompletion;
        }
        try self.construction.function_rewrites.ensureUnusedCapacity(allocator, 1);
        try self.construction.binding_rewrites.ensureUnusedCapacity(allocator, defaults.len);
        for (defaults) |entry| {
            const slot = &self.bindings.items[@intFromEnum(entry.binding)];
            self.construction.binding_rewrites.appendAssumeCapacity(.{
                .binding_id = entry.binding,
                .previous = slot.*,
                .resolution = if (self.isBindingTypeUnresolved(entry.binding)) .unresolved else .resolved,
            });
            slot.initialization = entry.value;
        }
        self.construction.function_rewrites.appendAssumeCapacity(.{ .id = id, .previous = self.functions.items[raw] });
        self.functions.items[raw].body = body;
    }

    /// Signature completion shares the body's ordered history; fields of one
    /// function must not be restored by independent journals in a fixed order.
    pub fn setFunction(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalFunctionId, value: Function) !void {
        const raw = @intFromEnum(id);
        const previous = self.functions.items[raw];
        if (previous.body != null and previous.body != value.body) return error.FunctionBodyAlreadyCompleted;
        if (self.mutation_frontier == null or raw < self.mutation_frontier.?.functions)
            try self.construction.function_rewrites.append(allocator, .{ .id = id, .previous = previous });
        self.functions.items[raw] = value;
    }

    pub fn setInferredErrorReasons(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalFunctionId, reasons: ?GlobalTypeId) !void {
        var updated = self.function(id);
        if (updated.inferred_error_reasons == reasons) return;
        updated.inferred_error_reasons = reasons;
        try self.setFunction(allocator, id, updated);
    }

    pub fn setErrorPropagation(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalErrorPropagationId, value: ErrorPropagation) !void {
        const raw = @intFromEnum(id);
        if (self.mutation_frontier == null or raw < self.mutation_frontier.?.error_propagations)
            try self.construction.error_propagation_rewrites.append(allocator, .{ .id = id, .previous = self.error_propagations.items[raw] });
        self.error_propagations.items[raw] = value;
    }

    pub fn setErrorContext(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalErrorContextId, value: ErrorContext) !void {
        const raw = @intFromEnum(id);
        if (self.mutation_frontier == null or raw < self.mutation_frontier.?.error_contexts)
            try self.construction.error_context_rewrites.append(allocator, .{ .id = id, .previous = self.error_contexts.items[raw] });
        self.error_contexts.items[raw] = value;
    }

    pub fn completeOperationBinding(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: ContractOperationBindingId, function_id: GlobalFunctionId) !void {
        const raw = @intFromEnum(id);
        const previous = self.contract_operation_bindings.items[raw].materialized_function;
        if (previous) |published| {
            std.debug.assert(published == function_id);
            return;
        }
        if (self.mutation_frontier == null or raw < self.mutation_frontier.?.contract_operation_bindings)
            try self.construction.operation_completions.append(allocator, .{ .id = id, .previous = previous });
        self.contract_operation_bindings.items[raw].materialized_function = function_id;
    }

    pub fn setContractConformance(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, index: u32, value: ContractConformance) !void {
        if (self.mutation_frontier == null or index < self.mutation_frontier.?.contract_conformances)
            try self.construction.conformance_rewrites.append(allocator, .{ .index = index, .previous = self.contract_conformances.items[index] });
        self.contract_conformances.items[index] = value;
    }

    pub fn hasPendingTypeDefinitionCompletion(self: *const GlobalSemanticGraph, id: GlobalTypeDefinitionId) bool {
        for (self.construction.definition_rewrites.items) |rewrite| if (rewrite.id == id) return true;
        return false;
    }

    pub fn completeTypeDefinition(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalTypeDefinitionId, value: TypeDefinition) !void {
        const raw = @intFromEnum(id);
        std.debug.assert(self.type_definitions.items[raw].struct_fields == null and self.type_definitions.items[raw].choice_variants == null);
        if (self.mutation_frontier == null or raw < self.mutation_frontier.?.type_definitions)
            try self.construction.definition_rewrites.append(allocator, .{ .id = id, .previous = self.type_definitions.items[raw] });
        self.type_definitions.items[raw] = value;
    }

    pub fn setVariant(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalVariantId, value: ChoiceVariant) !void {
        const raw = @intFromEnum(id);
        if (self.mutation_frontier == null or raw < self.mutation_frontier.?.variants)
            try self.construction.variant_rewrites.append(allocator, .{ .id = id, .previous = self.variants.items[raw] });
        self.variants.items[raw] = value;
    }

    pub fn setNodeType(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalNodeId, ty: ?GlobalTypeId) !void {
        var updated = self.node(id);
        if (updated.ty == ty) return;
        updated.ty = ty;
        try self.setNode(allocator, id, updated);
    }

    pub fn setNodeContent(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalNodeId, content: Node.Content) !void {
        var updated = self.node(id);
        updated.content = content;
        try self.setNode(allocator, id, updated);
    }

    pub fn setBlock(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalBlockId, value: Block) !void {
        const raw = @intFromEnum(id);
        if (self.mutation_frontier) |frontier| if (raw < frontier.blocks) {
            try self.construction.block_rewrites.append(allocator, .{ .id = id, .previous = self.blocks.items[raw] });
        };
        self.blocks.items[raw] = value;
    }

    /// Binding metadata and type resolution share one ordered undo history.
    /// Explicit type resolution remains responsible for its readiness marker.
    pub fn setBinding(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalBindingId, value: Binding) !void {
        try self.recordBindingRewrite(allocator, id);
        self.bindings.items[@intFromEnum(id)] = value;
    }

    /// Complete or annotate a node without retaining pointers into a growing pool.
    /// Reserve undo storage before changing a slot owned by an enclosing scope.
    pub fn setNode(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalNodeId, value: Node) !void {
        const raw = @intFromEnum(id);
        if (self.mutation_frontier) |frontier| if (raw < frontier.nodes) {
            try self.construction.node_rewrites.append(allocator, .{ .id = id, .previous = self.nodes.items[raw] });
        };
        self.nodes.items[raw] = value;
    }

    /// Publish a complete erased interface once, preserving the receiver slot.
    /// Older rows participate in rollback; new rows belong to the pool tail.
    pub fn completeVirtualSignature(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalVirtualRegistryId, contract: primitives.MethodSafetyContract, input_count: u32, output: GlobalTypeId) !void {
        const raw = @intFromEnum(id);
        if (raw >= self.virtual_registries.items.len or @intFromEnum(output) >= self.types.items.len) return error.InvalidVirtualSignatureCompletion;
        const previous = self.virtual_registries.items[raw];
        if (previous.contract_input_count != null) return error.VirtualSignatureAlreadyCompleted;
        if (previous.receiver_input_index >= input_count) return error.InvalidVirtualSignatureCompletion;
        if (self.mutation_frontier) |frontier| if (raw < frontier.virtual_registries) {
            try self.construction.virtual_completions.append(allocator, .{ .id = id, .previous = previous });
        };
        self.virtual_registries.items[raw] = .{
            .receiver_input_index = previous.receiver_input_index,
            .safety_contract = contract,
            .contract_input_count = input_count,
            .contract_output_type = output,
        };
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
        try self.recordBindingRewrite(allocator, id);
        try self.ensureBindingTypeResolutionCovers(allocator, self.bindings.items.len);
        self.construction.binding_type_resolution.items[raw] = .unresolved;
        self.bindings.items[raw].ty = unresolved_binding_type_poison;
    }

    /// Publish a binding type through the construction-state boundary. New
    /// resolution code should prefer this over patching the binding slot
    /// directly so provisional state is updated at the same time.
    pub fn resolveBindingType(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalBindingId, ty: GlobalTypeId) !void {
        const raw: usize = @intFromEnum(id);
        if (raw >= self.bindings.items.len) return error.InvalidGlobalBindingId;
        try self.recordBindingRewrite(allocator, id);
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
        // Relocation appends ordered, disjoint physical declaration ranges;
        // verifyModulePartitions checks that invariant before graph validation
        // uses this lookup. Empty modules and source fragments retain their own
        // positions. Canonical namespace ownership is a separate operation.
        return self.moduleForPartition("declarations", @intFromEnum(id));
    }

    pub fn moduleForTypeDefinition(self: *const GlobalSemanticGraph, id: GlobalTypeDefinitionId) ?GlobalModuleId {
        return self.moduleForPartition("files", self.typeDefinition(id).source.file_index);
    }

    fn moduleForPartition(self: *const GlobalSemanticGraph, comptime field: []const u8, raw: u32) ?GlobalModuleId {
        var first: usize = 0;
        var end = self.modules.items.len;
        while (first < end) {
            const middle = first + (end - first) / 2;
            const range = @field(self.modules.items[middle], field);
            if (raw < range.start) {
                end = middle;
            } else if (raw - range.start >= range.len) {
                first = middle + 1;
            } else return @enumFromInt(@as(u32, @intCast(middle)));
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
        return self.safety_batches.items.len * @sizeOf(*std.heap.ArenaAllocator) +
            self.modules.items.len * @sizeOf(Module) +
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
            self.captured_expressions.items.len * @sizeOf(CapturedExpression) +
            self.argument_default_temporaries.items.len * @sizeOf(ArgumentDefaultTemporary) +
            self.captured_expression_bindings.items.len * @sizeOf(CapturedExpressionBinding) +
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
    try graph.types.append(allocator, .{ .nominal = @enumFromInt(0) });
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
    graph.discardIndexedTail(allocator, 1, 3);
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

    graph.rollback(allocator, saved);
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

    try graph.resolveType(allocator, @enumFromInt(0), .{ .builtin = .Int32 });
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
    graph.rollback(allocator, inner);
    try std.testing.expectEqual(@as(u32, 1), graph.types.items[1].generic.arguments.start);
    try std.testing.expectEqual(@as(usize, 2), graph.generic_arguments.items.len);
    graph.rollback(allocator, outer);
    try std.testing.expectEqual(@as(u32, 0), graph.types.items[1].generic.arguments.start);
    try std.testing.expectEqual(@as(usize, 1), graph.generic_arguments.items.len);
    try std.testing.expectEqual(@as(usize, 0), graph.construction.type_rewrites.items.len);
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
    graph.rollback(allocator, saved);
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
    try copy.resolveType(allocator, @enumFromInt(0), .{ .builtin = .UInt8 });
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
    const domains = try arena.alloc(primitives.StorageDomainMapping, 1);
    const paths = try arena.alloc(primitives.StorageDomainMapping.Path, 1);
    paths[0] = .{ .fields = try arena.dupe(u32, &.{ 2, 5 }) };
    domains[0] = .{ .domain_index = 1, .paths = paths };
    try source.virtualizes.append(a, .{ .value = @enumFromInt(0), .concrete_type = @enumFromInt(0), .contract_decl = @enumFromInt(0), .virtual_type = @enumFromInt(0), .methods = .{ .start = 0, .len = 0 }, .safety_methods = .{ .start = 0, .len = 0 }, .source = location, .domains = domains });
    try source.contract_safety_conformances.append(a, .{
        .selection = .{ .conformance = 0, .index = 0 },
        .method = @enumFromInt(0),
        .contract = .{ .output_count = 1, .outcomes = outcomes, .source = location },
        .domains = domains,
        .receiver_input_index = null,
        .source = location,
    });
    try source.types.append(a, .{ .builtin = .Int32 });
    try source.virtual_registries.append(a, .{ .receiver_input_index = 0, .safety_contract = .{ .output_count = 1, .outcomes = outcomes, .source = location } });
    var transaction = source.beginTransaction(a);
    defer transaction.deinit();
    try source.completeVirtualSignature(a, @enumFromInt(0), .{ .output_count = 1, .outcomes = outcomes, .source = location }, 1, @enumFromInt(0));
    transaction.commit();
    var copy = try source.clone(allocator);
    defer copy.deinit(allocator);
    source.deinit(a);
    try std.testing.expectEqual(@as(u32, 3), copy.contract_safety_conformances.items[0].contract.outcomes[0].parent_variants[0]);
    try std.testing.expectEqual(@as(u32, 3), copy.construction.virtual_completions.items[0].previous.safety_contract.?.outcomes[0].parent_variants[0]);
    try std.testing.expectEqual(@as(u32, 5), copy.contract_safety_conformances.items[0].domains[0].paths[0].fields[1]);
    try std.testing.expectEqual(@as(u32, 5), copy.virtualizes.items[0].domains[0].paths[0].fields[1]);
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

fn functionCompletionGraph(allocator: std.mem.Allocator) !GlobalSemanticGraph {
    var graph: GlobalSemanticGraph = .{};
    errdefer graph.deinit(allocator);
    for (0..2) |_| {
        try graph.functions.append(allocator, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } });
        try graph.blocks.append(allocator, .{ .nodes = .{ .start = 0, .len = 0 } });
        try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .{ .int_literal = 7 } });
    }
    try graph.bindings.append(allocator, .{ .name = .{ .start = 0, .len = 0 }, .source = .{ .file_index = 0, .offset = 0 }, .ty = @enumFromInt(0), .mutability = .constant, .initialization = @enumFromInt(0) });
    return graph;
}

test "function completions preserve published bodies across nested rollback and pool growth" {
    const a = std.testing.allocator;
    var graph = try functionCompletionGraph(a);
    defer graph.deinit(a);
    const outer = graph.checkpoint();
    try graph.completeFunctionBody(a, @enumFromInt(0), @enumFromInt(0), &.{.{ .binding = @enumFromInt(0), .value = @enumFromInt(1) }});
    const inner = graph.checkpoint();
    try graph.completeFunctionBody(a, @enumFromInt(1), @enumFromInt(1), &.{.{ .binding = @enumFromInt(0), .value = @enumFromInt(0) }});
    try std.testing.expectError(error.FunctionBodyAlreadyCompleted, graph.completeFunctionBody(a, @enumFromInt(0), @enumFromInt(1), &.{}));
    for (0..64) |_| try graph.functions.append(a, graph.functions.items[0]);
    graph.rollback(a, inner);
    try std.testing.expectEqual(@as(usize, 2), graph.functions.items.len);
    try std.testing.expectEqual(@as(?GlobalBlockId, @enumFromInt(0)), graph.functions.items[0].body);
    try std.testing.expect(graph.functions.items[1].body == null);
    try std.testing.expectEqual(@as(?GlobalNodeId, @enumFromInt(1)), graph.bindings.items[0].initialization);
    graph.rollback(a, outer);
    try std.testing.expect(graph.functions.items[0].body == null);
    try std.testing.expectEqual(@as(?GlobalNodeId, @enumFromInt(0)), graph.bindings.items[0].initialization);
    try std.testing.expectEqualDeep(outer, graph.checkpoint());
}

fn completeFunctionWithAllocationFailures(allocator: std.mem.Allocator) !void {
    var graph = try functionCompletionGraph(allocator);
    defer graph.deinit(allocator);
    const saved = graph.checkpoint();
    errdefer {
        std.debug.assert(graph.function(@enumFromInt(0)).body == null);
        std.debug.assert(graph.binding(@enumFromInt(0)).initialization.? == @as(GlobalNodeId, @enumFromInt(0)));
        std.debug.assert(graph.construction.function_rewrites.items.len == saved.function_rewrites_len);
    }
    try graph.completeFunctionBody(allocator, @enumFromInt(0), @enumFromInt(0), &.{.{ .binding = @enumFromInt(0), .value = @enumFromInt(1) }});
    graph.rollback(allocator, saved);
    try std.testing.expectEqualDeep(saved, graph.checkpoint());
}

test "function completions leave published slots intact on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, completeFunctionWithAllocationFailures, .{});
}

fn resolutionTransactionGraph(allocator: std.mem.Allocator) !GlobalSemanticGraph {
    var graph: GlobalSemanticGraph = .{};
    errdefer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.markTypeUnresolved(allocator, @enumFromInt(0));
    try graph.bindings.append(allocator, .{ .name = .{ .start = 0, .len = 0 }, .source = .{ .file_index = 0, .offset = 0 }, .ty = @enumFromInt(0), .mutability = .constant });
    try graph.markBindingTypeUnresolved(allocator, @enumFromInt(0));
    return graph;
}

test "resolution transactions restore older holes after nested commit and pool growth" {
    const a = std.testing.allocator;
    var graph = try resolutionTransactionGraph(a);
    defer graph.deinit(a);
    const saved = graph.checkpoint();
    var outer = graph.beginTransaction(a);
    defer outer.deinit();
    try graph.types.append(a, .{ .builtin = .UInt8 });
    try graph.resolveType(a, @enumFromInt(0), .{ .builtin = .Int32 });
    try graph.resolveBindingType(a, @enumFromInt(0), @enumFromInt(1));
    var inner = graph.beginTransaction(a);
    defer inner.deinit();
    try graph.resolveType(a, @enumFromInt(0), .{ .builtin = .UInt64 });
    try graph.resolveBindingType(a, @enumFromInt(0), @enumFromInt(0));
    inner.commit();
    try std.testing.expectEqual(primitives.BuiltinType.UInt64, graph.semanticType(@enumFromInt(0)).builtin);
    for (0..64) |_| try graph.types.append(a, .{ .builtin = .UInt8 });
    outer.rollback();
    try std.testing.expect(graph.mutation_frontier == null);
    try std.testing.expect(graph.isTypeUnresolved(@enumFromInt(0)));
    try std.testing.expect(graph.resolvedSemanticType(@enumFromInt(0)) == null);
    try std.testing.expect(graph.isBindingTypeUnresolved(@enumFromInt(0)));
    try std.testing.expectEqual(unresolved_binding_type_poison, graph.binding(@enumFromInt(0)).ty);
    try std.testing.expectEqualDeep(saved, graph.checkpoint());
}

test "resolution transactions distinguish new tails from parent-owned slots" {
    const a = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    var outer = graph.beginTransaction(a);
    defer outer.deinit();
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.resolveType(a, @enumFromInt(0), .{ .builtin = .UInt8 });
    try std.testing.expectEqual(@as(usize, 0), graph.construction.type_rewrites.items.len);
    var inner = graph.beginTransaction(a);
    defer inner.deinit();
    try graph.markTypeUnresolved(a, @enumFromInt(0));
    try std.testing.expect(graph.isTypeUnresolved(@enumFromInt(0)));
    inner.rollback();
    try std.testing.expectEqual(primitives.BuiltinType.UInt8, graph.semanticType(@enumFromInt(0)).builtin);
    try std.testing.expect(!graph.isTypeUnresolved(@enumFromInt(0)));
    outer.rollback();
    try std.testing.expectEqual(@as(usize, 0), graph.types.items.len);
}

test "resolution transactions undo canonicalization and completion in write order" {
    const a = std.testing.allocator;
    var graph = try resolutionTransactionGraph(a);
    defer graph.deinit(a);
    const before = graph.checkpoint();
    var transaction = graph.beginTransaction(a);
    defer transaction.deinit();
    try graph.generic_arguments.append(a, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = @enumFromInt(0) } });
    try graph.resolveType(a, @enumFromInt(0), .{ .generic = .{ .base = @enumFromInt(0), .arguments = .{ .start = 0, .len = 1 } } });
    try graph.generic_arguments.append(a, graph.generic_arguments.items[0]);
    try graph.replaceTypeArguments(a, @enumFromInt(0), .{ .start = 1, .len = 1 });
    try graph.markTypeUnresolved(a, @enumFromInt(0));
    try graph.resolveType(a, @enumFromInt(0), .{ .builtin = .UInt8 });
    transaction.rollback();
    try std.testing.expect(graph.isTypeUnresolved(@enumFromInt(0)));
    try std.testing.expectEqual(unresolved_type_poison_definition, graph.semanticType(@enumFromInt(0)).nominal);
    try std.testing.expectEqualDeep(before, graph.checkpoint());
}

fn resolveWithAllocationFailures(allocator: std.mem.Allocator) !void {
    var graph = try resolutionTransactionGraph(allocator);
    defer graph.deinit(allocator);
    const before = graph.checkpoint();
    const scope = struct {
        fn attempt(alloc: std.mem.Allocator, target: *GlobalSemanticGraph) !void {
            var transaction = target.beginTransaction(alloc);
            defer transaction.deinit();
            try target.types.append(alloc, .{ .builtin = .UInt8 });
            try target.resolveType(alloc, @enumFromInt(0), .{ .builtin = .Int32 });
            try target.resolveBindingType(alloc, @enumFromInt(0), @enumFromInt(1));
        }
    };
    errdefer {
        std.debug.assert(graph.mutation_frontier == null);
        std.debug.assert(graph.isTypeUnresolved(@enumFromInt(0)));
        std.debug.assert(graph.isBindingTypeUnresolved(@enumFromInt(0)));
        std.debug.assert(std.meta.eql(before, graph.checkpoint()));
    }
    try scope.attempt(allocator, &graph);
    try std.testing.expectEqualDeep(before, graph.checkpoint());
}

test "resolution transactions restore holes and metadata on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resolveWithAllocationFailures, .{});
}

test "resolution transactions preserve accepted completions after later rejection" {
    const a = std.testing.allocator;
    var graph = try resolutionTransactionGraph(a);
    defer graph.deinit(a);
    var accepted = graph.beginTransaction(a);
    defer accepted.deinit();
    try graph.resolveType(a, @enumFromInt(0), .{ .builtin = .Int32 });
    try graph.resolveBindingType(a, @enumFromInt(0), @enumFromInt(0));
    accepted.commit();
    graph.commitCompletions(a);
    const saved = graph.checkpoint();
    var rejected = graph.beginTransaction(a);
    defer rejected.deinit();
    try graph.markTypeUnresolved(a, @enumFromInt(0));
    try graph.markBindingTypeUnresolved(a, @enumFromInt(0));
    rejected.rollback();
    try std.testing.expectEqual(primitives.BuiltinType.Int32, graph.semanticType(@enumFromInt(0)).builtin);
    try std.testing.expect(!graph.isTypeUnresolved(@enumFromInt(0)));
    try std.testing.expect(!graph.isBindingTypeUnresolved(@enumFromInt(0)));
    try std.testing.expectEqual(@as(GlobalTypeId, @enumFromInt(0)), graph.binding(@enumFromInt(0)).ty);
    try std.testing.expectEqualDeep(saved, graph.checkpoint());
}

test "rejected unique names retain no index entries or per-name allocations" {
    var memory = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const a = memory.allocator();
    {
        var graph: GlobalSemanticGraph = .{};
        defer graph.deinit(a);
        var retained: ?usize = null;
        for (0..1000) |index| {
            const saved = graph.checkpoint();
            var buffer: [32]u8 = undefined;
            const spelling = try std.fmt.bufPrint(&buffer, "rejected_{d:0>4}", .{index});
            const name = try graph.addString(a, spelling);
            try graph.declarations.append(a, .{ .kind = .function, .name = name, .source = .{ .file_index = 0, .offset = 0 } });
            try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } });
            try std.testing.expectEqual(@as(usize, 1), (try graph.functionsNamed(a, spelling)).len);
            try std.testing.expectEqual(@as(usize, 1), (try graph.declarationsNamed(a, spelling)).len);
            graph.rollback(a, saved);
            try std.testing.expectEqual(@as(u32, 0), graph.lookup.function_names.count());
            try std.testing.expectEqual(@as(u32, 0), graph.lookup.declaration_names.count());
            const live = memory.allocated_bytes - memory.freed_bytes;
            if (retained) |previous| try std.testing.expectEqual(previous, live) else retained = live;
        }
    }
    try std.testing.expectEqual(memory.allocated_bytes, memory.freed_bytes);
}

test "parameterized name indexes restore cursors and reject reused module identities" {
    const a = std.testing.allocator;
    var modules: [3]module_sg.ModuleSemanticGraph = @splat(.{});
    defer for (&modules) |*module| module.deinit(a);
    const names = [_][]const []const u8{ &.{"work"}, &.{ "work", "discarded" }, &.{"replacement"} };
    for (&modules, names) |*module, spellings| {
        module.module_dir = try a.dupe(u8, "module");
        for (spellings, 0..) |spelling, index| {
            const name = try semantic_strings.append(&module.strings, a, spelling);
            try module.declarations.append(a, .{ .kind = .function, .name = name, .source_offset = 0, .module_file_index = 0 });
            try module.semantic.parameterized_storage.parameterized_functions.append(a, .{
                .declaration = @enumFromInt(index),
                .parameters = .{ .start = 0, .len = 0 },
                .input = @enumFromInt(0),
                .output = @enumFromInt(0),
                .body = null,
            });
        }
    }
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    _ = try graph.parameterizedFunctionsNamed(a, modules[0..1], "work");
    const saved = graph.checkpoint();
    try std.testing.expectEqual(@as(usize, 2), (try graph.parameterizedFunctionsNamed(a, modules[0..2], "work")).len);
    try std.testing.expectEqual(@as(usize, 1), (try graph.parameterizedFunctionsNamed(a, modules[0..2], "discarded")).len);
    graph.rollback(a, saved);
    try std.testing.expectEqualDeep(saved, graph.checkpoint());
    try std.testing.expectEqual(@as(u32, 1), graph.lookup.parameterized_function_names.count());
    const replacement = [_]module_sg.ModuleSemanticGraph{ modules[0], modules[2] };
    try std.testing.expectEqual(@as(usize, 0), (try graph.parameterizedFunctionsNamed(a, &replacement, "discarded")).len);
    try std.testing.expectEqual(@as(usize, 1), (try graph.parameterizedFunctionsNamed(a, &replacement, "work")).len);
    const selected = try graph.parameterizedFunctionsNamed(a, &replacement, "replacement");
    try std.testing.expectEqual(@as(usize, 1), selected.len);
    try std.testing.expectEqual(@as(u32, 1), selected[0].module_index);
}

fn indexNamesWithAllocationFailures(allocator: std.mem.Allocator) !void {
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const scope = struct {
        fn attempt(a: std.mem.Allocator, target: *GlobalSemanticGraph) !void {
            var transaction = target.beginTransaction(a);
            defer transaction.deinit();
            const name = try target.addString(a, "discarded");
            try target.declarations.append(a, .{ .kind = .function, .name = name, .source = .{ .file_index = 0, .offset = 0 } });
            try target.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } });
            _ = try target.functionsNamed(a, "discarded");
            _ = try target.declarationsNamed(a, "discarded");
        }
    };
    errdefer {
        std.debug.assert(graph.lookup.function_names.count() == 0);
        std.debug.assert(graph.lookup.declaration_names.count() == 0);
    }
    try scope.attempt(allocator, &graph);
    try std.testing.expectEqual(@as(u32, 0), graph.lookup.function_names.count());
    try std.testing.expectEqual(@as(u32, 0), graph.lookup.declaration_names.count());
}

test "name indexes publish keys atomically under allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, indexNamesWithAllocationFailures, .{});
}

test "metadata batches bound memory across repeated rejected transactions" {
    var memory = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const a = memory.allocator();
    {
        var graph: GlobalSemanticGraph = .{};
        defer graph.deinit(a);
        const accepted = try (try graph.safetyAllocator(a)).dupe(u8, "accepted");
        const arena = graph.safety_arena;
        var retained: ?usize = null;
        for (0..1000) |_| {
            var transaction = graph.beginTransaction(a);
            defer transaction.deinit();
            const scratch = try (try graph.safetyAllocator(a)).alloc(u8, 4096);
            @memset(scratch, 42);
            try std.testing.expect(graph.safety_arena != arena);
            transaction.rollback();
            try std.testing.expectEqual(arena, graph.safety_arena);
            try std.testing.expectEqual(@as(usize, 1), graph.safety_batches.items.len);
            try std.testing.expectEqualStrings("accepted", accepted);
            const live = memory.allocated_bytes - memory.freed_bytes;
            if (retained) |previous| try std.testing.expectEqual(previous, live) else retained = live;
        }
    }
    try std.testing.expectEqual(memory.allocated_bytes, memory.freed_bytes);
}

test "metadata batches keep committed children until the enclosing decision" {
    const a = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const accepted = try (try graph.safetyAllocator(a)).dupe(u8, "accepted");
    var outer = graph.beginTransaction(a);
    defer outer.deinit();
    const parent = try (try graph.safetyAllocator(a)).dupe(u8, "parent");
    const parent_arena = graph.safety_arena;
    var child = graph.beginTransaction(a);
    defer child.deinit();
    const nested = try (try graph.safetyAllocator(a)).dupe(u8, "child");
    child.commit();
    try std.testing.expectEqual(parent_arena, graph.safety_arena);
    try std.testing.expectEqualStrings("child", nested);
    try std.testing.expectEqualStrings("parent", parent);
    try std.testing.expectEqual(@as(usize, 3), graph.safety_batches.items.len);
    outer.rollback();
    try std.testing.expectEqual(@as(usize, 1), graph.safety_batches.items.len);
    try std.testing.expectEqualStrings("accepted", accepted);
    var committed = graph.beginTransaction(a);
    defer committed.deinit();
    const published = try (try graph.safetyAllocator(a)).dupe(u8, "published");
    committed.commit();
    graph.commitCompletions(a);
    var rejected = graph.beginTransaction(a);
    defer rejected.deinit();
    _ = try (try graph.safetyAllocator(a)).alloc(u8, 4096);
    rejected.rollback();
    try std.testing.expectEqual(@as(usize, 2), graph.safety_batches.items.len);
    try std.testing.expectEqualStrings("published", published);
    try std.testing.expectEqualStrings("accepted", accepted);
}

test "virtual signature completions restore prior metadata and allocation owners" {
    const a = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    const old = try (try graph.safetyAllocator(a)).alloc(primitives.MethodSafetyContract.Outcome, 1);
    old[0] = .{ .variant = .{ .start = 0, .len = 0 }, .parent_variants = &.{3}, .source = source };
    try graph.virtual_registries.append(a, .{ .receiver_input_index = 0, .safety_contract = .{ .output_count = 1, .outcomes = old, .source = source } });
    const saved = graph.checkpoint();
    var transaction = graph.beginTransaction(a);
    defer transaction.deinit();
    const fresh = try (try graph.safetyAllocator(a)).dupe(primitives.MethodSafetyContract.Outcome, old);
    fresh[0].parent_variants = &.{7};
    const declared: primitives.MethodSafetyContract = .{ .output_count = 1, .outcomes = fresh, .source = source };
    try graph.completeVirtualSignature(a, @enumFromInt(0), declared, 1, @enumFromInt(0));
    try std.testing.expectEqual(@as(u32, 7), graph.virtual_registries.items[0].safety_contract.?.outcomes[0].parent_variants[0]);
    try std.testing.expectError(error.VirtualSignatureAlreadyCompleted, graph.completeVirtualSignature(a, @enumFromInt(0), declared, 1, @enumFromInt(0)));
    transaction.rollback();
    try std.testing.expectEqualDeep(saved, graph.checkpoint());
    try std.testing.expect(graph.virtual_registries.items[0].contract_input_count == null);
    try std.testing.expectEqual(@as(u32, 3), graph.virtual_registries.items[0].safety_contract.?.outcomes[0].parent_variants[0]);
}

fn completeVirtualWithAllocationFailures(allocator: std.mem.Allocator) !void {
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.virtual_registries.append(allocator, .{ .receiver_input_index = 0 });
    const saved = graph.checkpoint();
    const scope = struct {
        fn attempt(a: std.mem.Allocator, target: *GlobalSemanticGraph) !void {
            var transaction = target.beginTransaction(a);
            defer transaction.deinit();
            const arena = try target.safetyAllocator(a);
            const outcomes = try arena.alloc(primitives.MethodSafetyContract.Outcome, 1);
            outcomes[0] = .{ .variant = .{ .start = 0, .len = 0 }, .source = .{ .file_index = 0, .offset = 0 } };
            try target.completeVirtualSignature(a, @enumFromInt(0), .{ .output_count = 1, .outcomes = outcomes, .source = outcomes[0].source }, 1, @enumFromInt(0));
        }
    };
    errdefer {
        std.debug.assert(graph.virtual_registries.items[0].contract_input_count == null);
        std.debug.assert(graph.safety_batches.items.len == 0);
        std.debug.assert(std.meta.eql(saved, graph.checkpoint()));
    }
    try scope.attempt(allocator, &graph);
    try std.testing.expectEqualDeep(saved, graph.checkpoint());
}

test "virtual signature completions release staged metadata on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, completeVirtualWithAllocationFailures, .{});
}

test "node completions restore enclosing state after nested commit and pool growth" {
    const a = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const original: Node = .{ .source = .{ .file_index = 0, .offset = 7 }, .ty = null, .content = .{ .int_literal = 1 } };
    try graph.nodes.append(a, original);
    const saved = graph.checkpoint();
    var outer = graph.beginTransaction(a);
    defer outer.deinit();
    var completed = original;
    completed.content = .{ .int_literal = 2 };
    try graph.setNode(a, @enumFromInt(0), completed);
    try graph.nodes.append(a, original);
    try graph.setNode(a, @enumFromInt(1), completed);
    try std.testing.expectEqual(@as(usize, 1), graph.construction.node_rewrites.items.len);
    var child = graph.beginTransaction(a);
    defer child.deinit();
    completed.content = .{ .int_literal = 3 };
    try graph.setNode(a, @enumFromInt(0), completed);
    try graph.setNode(a, @enumFromInt(1), completed);
    child.commit();
    for (0..128) |_| try graph.nodes.append(a, original);
    outer.rollback();
    try std.testing.expectEqualDeep(original, graph.node(@enumFromInt(0)));
    try std.testing.expectEqualDeep(saved, graph.checkpoint());
}

test "node completion allocation failure leaves the original slot untouched" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(a: std.mem.Allocator) !void {
            var graph: GlobalSemanticGraph = .{};
            defer graph.deinit(a);
            const original: Node = .{ .source = .{ .file_index = 0, .offset = 3 }, .ty = null, .content = .{ .int_literal = 1 } };
            try graph.nodes.append(a, original);
            const saved = graph.checkpoint();
            var transaction = graph.beginTransaction(a);
            defer transaction.deinit();
            errdefer {
                transaction.rollback();
                std.debug.assert(std.meta.eql(saved, graph.checkpoint()));
                std.debug.assert(std.meta.eql(original, graph.node(@enumFromInt(0))));
            }
            var completed = original;
            completed.content = .{ .int_literal = 9 };
            try graph.setNode(a, @enumFromInt(0), completed);
            transaction.rollback();
            try std.testing.expectEqualDeep(original, graph.node(@enumFromInt(0)));
            try std.testing.expectEqualDeep(saved, graph.checkpoint());
        }
    }.run, .{});
}

test "binding and block completions share ordered rollback with function defaults" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(a: std.mem.Allocator) !void {
            var graph = try resolutionTransactionGraph(a);
            defer graph.deinit(a);
            try graph.blocks.append(a, .{ .nodes = .{ .start = 0, .len = 0 } });
            try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } });
            try graph.nodes.append(a, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = @enumFromInt(0), .content = .{ .int_literal = 42 } });
            const original_binding = graph.binding(@enumFromInt(0));
            const original_block = graph.blocks.items[0];
            const saved = graph.checkpoint();
            var outer = graph.beginTransaction(a);
            defer outer.deinit();
            errdefer {
                outer.rollback();
                std.debug.assert(std.meta.eql(original_binding, graph.binding(@enumFromInt(0))));
                std.debug.assert(std.meta.eql(original_block, graph.blocks.items[0]));
                std.debug.assert(std.meta.eql(saved, graph.checkpoint()));
            }
            var updated = original_binding;
            updated.deferred_initialization = true;
            try graph.setBinding(a, @enumFromInt(0), updated);
            try graph.resolveBindingType(a, @enumFromInt(0), @enumFromInt(0));
            var child = graph.beginTransaction(a);
            defer child.deinit();
            try graph.completeFunctionBody(a, @enumFromInt(0), @enumFromInt(0), &.{.{ .binding = @enumFromInt(0), .value = @enumFromInt(0) }});
            updated = graph.binding(@enumFromInt(0));
            updated.deferred_initialization = false;
            try graph.setBinding(a, @enumFromInt(0), updated);
            try graph.setBlock(a, @enumFromInt(0), .{ .nodes = .{ .start = 0, .len = 0 }, .ret_val = @enumFromInt(0) });
            child.commit();
            for (0..64) |_| {
                try graph.bindings.append(a, original_binding);
                try graph.blocks.append(a, original_block);
            }
            outer.rollback();
            try std.testing.expectEqualDeep(original_binding, graph.binding(@enumFromInt(0)));
            try std.testing.expectEqualDeep(original_block, graph.blocks.items[0]);
            try std.testing.expect(graph.function(@enumFromInt(0)).body == null);
            try std.testing.expect(graph.isBindingTypeUnresolved(@enumFromInt(0)));
            try std.testing.expectEqualDeep(saved, graph.checkpoint());
        }
    }.run, .{});
}

test "function signatures bodies and propagated cleanup restore one enclosing decision" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(a: std.mem.Allocator) !void {
            var graph: GlobalSemanticGraph = .{};
            defer graph.deinit(a);
            const original: Function = .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 } };
            const propagation = std.mem.zeroes(ErrorPropagation);
            const context = std.mem.zeroes(ErrorContext);
            const conformance = std.mem.zeroes(ContractConformance);
            const variant = std.mem.zeroes(ChoiceVariant);
            try graph.functions.append(a, original);
            try graph.error_propagations.append(a, propagation);
            try graph.error_contexts.append(a, context);
            try graph.contract_conformances.append(a, conformance);
            const operation = std.mem.zeroes(ContractOperationBinding);
            try graph.contract_operation_bindings.append(a, operation);
            try graph.variants.append(a, variant);
            try graph.blocks.append(a, .{ .nodes = .{ .start = 0, .len = 0 } });
            try graph.types.append(a, .{ .builtin = .Int32 });
            const saved = graph.checkpoint();
            var outer = graph.beginTransaction(a);
            defer outer.deinit();
            errdefer {
                outer.rollback();
                std.debug.assert(std.meta.eql(original, graph.function(@enumFromInt(0))));
                std.debug.assert(std.meta.eql(propagation, graph.error_propagations.items[0]));
                std.debug.assert(std.meta.eql(context, graph.error_contexts.items[0]));
                std.debug.assert(std.meta.eql(conformance, graph.contract_conformances.items[0]));
                std.debug.assert(std.meta.eql(operation, graph.contract_operation_bindings.items[0]));
                std.debug.assert(std.meta.eql(variant, graph.variants.items[0]));
                std.debug.assert(std.meta.eql(saved, graph.checkpoint()));
            }
            try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .source = .{ .file_index = 0, .offset = 0 }, .ty = @enumFromInt(0) });
            var extended = original;
            extended.input.len = 1;
            try graph.setFunction(a, @enumFromInt(0), extended);
            try graph.completeFunctionBody(a, @enumFromInt(0), @enumFromInt(0), &.{});
            var child = graph.beginTransaction(a);
            defer child.deinit();
            try graph.setInferredErrorReasons(a, @enumFromInt(0), @enumFromInt(0));
            var updated_propagation = propagation;
            updated_propagation.ok_value_field_index = 1;
            try graph.setErrorPropagation(a, @enumFromInt(0), updated_propagation);
            var updated_context = context;
            updated_context.ok_value_field_index = 2;
            try graph.setErrorContext(a, @enumFromInt(0), updated_context);
            var validated = conformance;
            try graph.completeOperationBinding(a, @enumFromInt(0), @enumFromInt(0));
            validated.operation_bindings = .{ .start = 0, .len = 1 };
            validated.declaration_validated = true;
            try graph.setContractConformance(a, 0, validated);
            var resolved_variant = variant;
            resolved_variant.option_decl = @enumFromInt(0);
            try graph.setVariant(a, @enumFromInt(0), resolved_variant);
            child.commit();
            var invalid = graph.function(@enumFromInt(0));
            invalid.body = null;
            try std.testing.expectError(error.FunctionBodyAlreadyCompleted, graph.setFunction(a, @enumFromInt(0), invalid));
            for (0..64) |_| try graph.functions.append(a, original);
            outer.rollback();
            try std.testing.expectEqualDeep(original, graph.function(@enumFromInt(0)));
            try std.testing.expectEqualDeep(propagation, graph.error_propagations.items[0]);
            try std.testing.expectEqualDeep(context, graph.error_contexts.items[0]);
            try std.testing.expectEqualDeep(conformance, graph.contract_conformances.items[0]);
            try std.testing.expectEqualDeep(operation, graph.contract_operation_bindings.items[0]);
            try std.testing.expectEqualDeep(variant, graph.variants.items[0]);
            try std.testing.expectEqualDeep(saved, graph.checkpoint());
        }
    }.run, .{});
}

test "module ownership lookup preserves empty partitions fragments and rollback" {
    const a = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    for ([_]u32{ 0, 2, 0, 0, 3, 0, 1, 0 }) |length| {
        const start = if (graph.modules.items.len == 0) 0 else last: {
            const previous = graph.modules.items[graph.modules.items.len - 1].declarations;
            break :last previous.start + previous.len;
        };
        try graph.modules.append(a, .{ .dir = .{ .start = 0, .len = 0 }, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = start, .len = length } });
    }
    // An appended fragment belongs physically to itself and logically to its
    // original namespace; lookup must not collapse these two identities.
    graph.modules.items[6].namespace = @enumFromInt(1);
    for ([_]u32{ 1, 1, 4, 4, 4, 6 }, 0..) |owner, raw| {
        try std.testing.expectEqual(@as(?GlobalModuleId, @enumFromInt(owner)), graph.moduleForDeclaration(@enumFromInt(raw)));
    }
    try std.testing.expectEqual(@as(GlobalModuleId, @enumFromInt(1)), graph.moduleNamespace(graph.moduleForDeclaration(@enumFromInt(5)).?));
    try std.testing.expectEqual(null, graph.moduleForDeclaration(@enumFromInt(6)));
    try std.testing.expectEqual(null, graph.moduleForDeclaration(@enumFromInt(std.math.maxInt(u32))));
    const saved = graph.checkpoint();
    try graph.modules.append(a, .{ .dir = .{ .start = 0, .len = 0 }, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 6, .len = 2 } });
    try std.testing.expectEqual(@as(?GlobalModuleId, @enumFromInt(8)), graph.moduleForDeclaration(@enumFromInt(7)));
    graph.rollback(a, saved);
    try std.testing.expectEqual(null, graph.moduleForDeclaration(@enumFromInt(7)));
    graph.modules.clearRetainingCapacity();
    try std.testing.expectEqual(null, graph.moduleForDeclaration(@enumFromInt(0)));
}

test "nominal definition completion rolls back without changing identity" {
    const a = std.testing.allocator;
    var graph: GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const id: GlobalTypeDefinitionId = @enumFromInt(0);
    try graph.type_definitions.append(a, .{ .source = .{ .file_index = 0, .offset = 7 } });
    var transaction = graph.beginTransaction(a);
    defer transaction.deinit();
    var complete = graph.typeDefinition(id);
    complete.struct_fields = .{ .start = 0, .len = 0 };
    try graph.completeTypeDefinition(a, id, complete);
    try std.testing.expect(graph.typeDefinition(id).struct_fields != null);
    transaction.rollback();
    try std.testing.expectEqual(@as(usize, 1), graph.type_definitions.items.len);
    try std.testing.expectEqual(null, graph.typeDefinition(id).struct_fields);
    try std.testing.expectEqual(@as(u32, 7), graph.typeDefinition(id).source.offset);
}
