const entry_interface = @import("../../entry_interface.zig");
const type_arguments = @import("../type_arguments.zig");
const std = @import("std");
const literals = @import("../../semantic_literals.zig");
const syn = @import("../../../3_syntax/syntax_tree.zig");
const tok = @import("../../../2_tokens/token.zig");
const graph_mod = @import("../graph.zig");
const entities = @import("../entities.zig");
const writer_mod = @import("../writer.zig");
const views = @import("../views.zig");
const type_lowerer = @import("../type_lowerer.zig");
const parameterized_storage = @import("storage.zig");
const ir = @import("ir.zig");
const primitives = @import("../../primitives/schema.zig");

pub const Stats = struct {
    generic_types: u32 = 0,
    generic_functions: u32 = 0,
    contract_definitions: u32 = 0,
};

pub const ParameterBinding = struct {
    name: []const u8,
    id: ir.ComptimeParameterId,
    kind: parameterized_storage.ComptimeParameterKind,
};

const BindingName = struct {
    name: []const u8,
    id: ir.ParameterizedBindingId,
    assumed: bool = false,
};

pub fn lower(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !Stats {
    return lowerDiagnosed(allocator, graph, files, null);
}

pub fn lowerDiagnosed(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    diagnostics: ?*@import("../../../1_base/diagnostic.zig").Diagnostics,
) !Stats {
    var ctx = Context{
        .allocator = allocator,
        .graph = graph,
        .files = files,
        .writer = writer_mod.Writer.init(allocator, graph),
        .parameters = std.array_list.Managed(ParameterBinding).init(allocator),
        .bindings = std.array_list.Managed(BindingName).init(allocator),
        .diagnostics = diagnostics,
    };
    defer ctx.parameters.deinit();
    defer ctx.bindings.deinit();
    return ctx.lowerDeclarations();
}

pub const EntryCaptureSource = struct {
    pub const Value = union(enum) { value: entities.ModuleNodeId, owner: ?entities.ModuleFunctionId };
    context: *anyopaque,
    resolve: *const fn (*anyopaque, syn.NodeIndex, []const u8) anyerror!?Value,
};

/// Retain an anonymous entry body in the ordinary staged-function representation.
/// Its declared inputs/outputs are the only bindings initially in scope.
pub fn lowerConcreteEntry(graph: *graph_mod.ModuleSemanticGraph, writer: *writer_mod.Writer, file_index: u32, tree: *const syn.FileSyntaxTree, source: []const u8, node: syn.NodeIndex, declaration: entities.ModuleDeclId, function: entities.ModuleFunctionId, captures: EntryCaptureSource) !void {
    var context = Context{
        .allocator = writer.allocator,
        .graph = graph,
        .files = &.{},
        .writer = writer.*,
        .parameters = std.array_list.Managed(ParameterBinding).init(writer.allocator),
        .bindings = std.array_list.Managed(BindingName).init(writer.allocator),
        .file_index = file_index,
        .tree = tree,
        .source = source,
        .inside_comptime_entry = true,
        .module_capture_source = captures,
    };
    defer context.entry_captures.deinit(writer.allocator);
    defer context.parameters.deinit();
    defer context.bindings.deinit();
    const entry = tree.comptimeEntry(node).?;
    const empty = try context.addType(.{ .resolved = .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } } });
    const input = if (entry.input) |syntax| try context.lowerType(syntax, false) else empty;
    const input_bindings: primitives.Range(ir.ParameterizedBindingId) = if (entry.input) |syntax| try context.seedFunctionBindings(syntax, .constant) else .{ .start = 0, .len = 0 };
    const output = if (entry.output) |syntax| try context.lowerType(syntax, false) else empty;
    const output_bindings: primitives.Range(ir.ParameterizedBindingId) = if (entry.output) |syntax| try context.seedFunctionBindings(syntax, .variable) else .{ .start = 0, .len = 0 };
    const body = try context.lowerBlock(entry.body);
    try writer.addParameterizedFunction(.{
        .declaration = declaration,
        .is_comptime_entry = true,
        .concrete_function = function,
        .parameters = .{ .start = 0, .len = 0 },
        .input = input,
        .input_bindings = input_bindings,
        .output = output,
        .body = body,
        .output_bindings = output_bindings,
    });
}

/// Retain a closed expression for staged evaluation in the supplied module.
pub fn lowerConcreteExpression(graph: *graph_mod.ModuleSemanticGraph, writer: *writer_mod.Writer, file_index: u32, tree: *const syn.FileSyntaxTree, source: []const u8, node: syn.NodeIndex) !ir.ParameterizedNodeId {
    var context = Context{
        .allocator = writer.allocator,
        .graph = graph,
        .files = &.{},
        .writer = writer.*,
        .parameters = std.array_list.Managed(ParameterBinding).init(writer.allocator),
        .bindings = std.array_list.Managed(BindingName).init(writer.allocator),
        .file_index = file_index,
        .tree = tree,
        .source = source,
    };
    defer context.parameters.deinit();
    defer context.bindings.deinit();
    return context.lowerBodyNode(node);
}

pub fn lowerConcreteTypeExpression(graph: *graph_mod.ModuleSemanticGraph, writer: *writer_mod.Writer, file_index: u32, tree: *const syn.FileSyntaxTree, source: []const u8, node: syn.NodeIndex) !ir.ParameterizedTypeId {
    var context = Context{
        .allocator = writer.allocator,
        .graph = graph,
        .files = &.{},
        .writer = writer.*,
        .parameters = std.array_list.Managed(ParameterBinding).init(writer.allocator),
        .bindings = std.array_list.Managed(BindingName).init(writer.allocator),
        .file_index = file_index,
        .tree = tree,
        .source = source,
    };
    defer context.parameters.deinit();
    defer context.bindings.deinit();
    return context.lowerType(node, false);
}

pub fn lowerConcreteArguments(graph: *graph_mod.ModuleSemanticGraph, writer: *writer_mod.Writer, file_index: u32, tree: *const syn.FileSyntaxTree, source: []const u8, node: syn.NodeIndex) !primitives.Range(ir.ParameterizedGenericArgId) {
    var context = Context{
        .allocator = writer.allocator,
        .graph = graph,
        .files = &.{},
        .writer = writer.*,
        .parameters = std.array_list.Managed(ParameterBinding).init(writer.allocator),
        .bindings = std.array_list.Managed(BindingName).init(writer.allocator),
        .file_index = file_index,
        .tree = tree,
        .source = source,
    };
    defer context.parameters.deinit();
    defer context.bindings.deinit();
    const literal = tree.specializationArguments(node) orelse return error.InvalidGenericCallArguments;
    var arguments: std.ArrayList(ir.GenericArgument) = .empty;
    defer arguments.deinit(writer.allocator);
    for (literal.fields) |field_node| {
        const field = tree.structTypeField(field_node) orelse return error.InvalidGenericCallArgument;
        try arguments.append(writer.allocator, .{
            .name = try writer.addString(type_arguments.name(tree, source, field, "")),
            .value = if (field.type_node) |ty|
                .{ .type = try context.lowerType(ty, false) }
            else if (field.default_value) |value|
                try context.lowerGenericValue(value, false)
            else
                return error.InvalidGenericCallArgument,
        });
    }
    const start: u32 = @intCast(graph.semantic.parameterized_storage.ir.generic_arguments.items.len);
    try graph.semantic.parameterized_storage.ir.generic_arguments.appendSlice(writer.allocator, arguments.items);
    return .{ .start = start, .len = @intCast(arguments.items.len) };
}

const PipeOperandOverride = struct { syntax: syn.NodeIndex, value: ir.ParameterizedNodeId };

pub const Context = struct {
    in_defer: bool = false,
    defer_loop_depth: u32 = 0,
    diagnostics: ?*@import("../../../1_base/diagnostic.zig").Diagnostics = null,
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    writer: writer_mod.Writer,
    parameters: std.array_list.Managed(ParameterBinding),
    referenced_parameter_prefix: usize = 0,
    inside_comptime_entry: bool = false,
    generated_source: ?primitives.SourceRef = null,
    entry_parent: ?*Context = null,
    module_capture_source: ?EntryCaptureSource = null,
    entry_captures: std.ArrayList(struct { name: []const u8, use_node: ir.ParameterizedNodeId }) = .empty,
    bindings: std.array_list.Managed(BindingName),
    file_index: u32 = 0,
    tree: *const syn.FileSyntaxTree = undefined,
    source: []const u8 = &.{},
    temporary_declarations: ?*std.ArrayList(ir.ParameterizedNodeId) = null,
    pipe_value: ?ir.ParameterizedNodeId = null,
    pipe_operand_overrides: []const PipeOperandOverride = &.{},

    fn lowerDeclarations(self: *Context) !Stats {
        var stats: Stats = .{};
        var raw_decl: usize = 0;
        while (raw_decl < self.graph.declarations.items.len) : (raw_decl += 1) {
            const declaration = self.graph.declarations.items[raw_decl];
            self.file_index = declaration.module_file_index;
            const file = self.files[@intCast(self.file_index)];
            self.tree = file.tree;
            self.source = file.source;
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, declaration) orelse continue;
            const decl_id: entities.ModuleDeclId = @enumFromInt(@as(u32, @intCast(raw_decl)));

            switch (declaration.kind) {
                .type => {
                    const payload = self.genericTypePayload(declaration_node) orelse continue;
                    if (!hasGenericParameters(payload.params, payload.params_struct)) continue;
                    self.parameters.clearRetainingCapacity();
                    const params = try self.lowerParameters(payload.params, payload.params_struct);
                    const body = try self.lowerType(payload.value, false);
                    if (self.tree.tag(declaration_node) == .c_struct_declaration)
                        self.graph.semantic.parameterized_storage.ir.types.items[@intFromEnum(self.graph.semantic.parameterized_storage.ir.types.items[@intFromEnum(body)].definition.body)].resolved.structural.layout = .c_struct
                    else if (self.tree.tag(declaration_node) == .c_union_declaration)
                        self.graph.semantic.parameterized_storage.ir.types.items[@intFromEnum(self.graph.semantic.parameterized_storage.ir.types.items[@intFromEnum(body)].definition.body)].resolved.structural.layout = .c_union;
                    try self.writer.addParameterizedType(.{
                        .declaration = decl_id,
                        .parameters = params,
                        .body = body,
                    });
                    stats.generic_types += 1;
                },
                .function, .test_function => {
                    const function = if (declaration.kind == .test_function) self.tree.testDeclaration(declaration_node).?.function else self.tree.functionDeclaration(declaration_node) orelse continue;
                    self.parameters.clearRetainingCapacity();
                    self.bindings.clearRetainingCapacity();
                    const explicit = hasGenericParameters(function.generic_params, function.generic_params_struct);
                    const parameter_start: u32 = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len);
                    if (explicit) {
                        const registered = try self.registerParameters(function.generic_params, function.generic_params_struct);
                        // Inline members bind compiler-level associated elements.
                        // Their Int marker is not a runtime numeric contract.
                        if (!function.contract_member) try self.lowerParameterBounds(registered, function.generic_params_struct);
                    }
                    const params: primitives.Range(ir.ComptimeParameterId) = .{
                        .start = parameter_start,
                        .len = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len - parameter_start),
                    };
                    const staged_body = if (function.body) |body| self.tree.hasComptimeSelection(body) else false;
                    if (params.len == 0 and !function.contract_member and !staged_body) continue;
                    const input = try self.lowerType(function.input, false);
                    const output = try self.lowerType(function.output, false);
                    const input_bindings = try self.seedFunctionBindings(function.input, .constant);
                    const output_bindings = try self.seedFunctionBindings(function.output, .variable);
                    const body = if (function.body) |node| try self.lowerBlock(node) else null;
                    try self.writer.addParameterizedFunction(.{
                        .declaration = decl_id,
                        .concrete_function = if (params.len == 0 and staged_body) declaration.function_id else null,
                        .parameters = params,
                        .input = input,
                        .output = output,
                        .body = body,
                        .input_bindings = input_bindings,
                        .output_bindings = output_bindings,
                    });
                    stats.generic_functions += 1;
                },
                .contract_type => {
                    const contract = self.tree.contractDeclaration(declaration_node) orelse continue;
                    self.parameters.clearRetainingCapacity();
                    const params = try self.registerParameters(contract.generic_params, contract.generic_params_struct);
                    for (self.parameters.items, 0..) |binding, position| {
                        if (std.mem.eql(u8, binding.name, "Self")) try self.contractError(declaration_node, "associated contract members cannot be named Self; use named participants");
                        for (self.parameters.items[0..position]) |previous| {
                            if (std.mem.eql(u8, previous.name, binding.name))
                                try self.contractError(declaration_node, "duplicate associated contract member name");
                        }
                    }
                    const participants = if (contract.participants_struct) |participant_node| blk: {
                        const literal = self.tree.parameterList(participant_node).?;
                        if (literal.fields.len == 0) try self.contractError(declaration_node, "contract requires at least one named participant");
                        for (literal.fields) |field_node| {
                            const field = self.tree.structTypeField(field_node).?;
                            if (field.position != null or field.type_node == null or !isTypeParameter(self.tree, self.source, field) or field.default_value != null)
                                try self.contractError(field_node, "contract participants must be named Type parameters without defaults");
                        }
                        const range = try self.registerParameters(literal.fields, participant_node);
                        for (self.parameters.items, 0..) |parameter_binding, position| {
                            if (std.mem.eql(u8, parameter_binding.name, "Self")) try self.contractError(declaration_node, "explicit contract participants cannot be named Self");
                            for (self.parameters.items[0..position]) |previous| {
                                if (std.mem.eql(u8, previous.name, parameter_binding.name)) try self.contractError(declaration_node, "duplicate participant or associated parameter name");
                            }
                        }
                        if (contract.domains.len != 0 and literal.fields.len != 1) try self.contractError(declaration_node, "storage domains currently require a unary contract");
                        break :blk range;
                    } else primitives.Range(ir.ComptimeParameterId){ .start = 0, .len = 0 };
                    // Both groups are visible before any bound is lowered.
                    try self.lowerParameterBounds(params, contract.generic_params_struct);
                    try self.lowerParameterBounds(participants, contract.participants_struct);
                    const composition_start: u32 = @intCast(self.graph.semantic.parameterized_storage.contract_constraints.items.len);
                    for (contract.requires_contracts) |composed| _ = try self.lowerContractConstraint(composed);
                    const composition: primitives.Range(parameterized_storage.ContractConstraintId) = .{
                        .start = composition_start,
                        .len = @intCast(contract.requires_contracts.len),
                    };
                    const req_start: u32 = @intCast(self.graph.semantic.parameterized_storage.contract_requirements.items.len);
                    var domains: std.ArrayList(primitives.StringRange) = .empty;
                    defer domains.deinit(self.allocator);
                    for (contract.domains) |domain| {
                        const text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(domain));
                        for (domains.items) |previous| {
                            if (std.mem.eql(u8, self.graph.text(previous), text)) {
                                try self.contractError(domain, "duplicate Contract storage domain");
                                unreachable;
                            }
                        }
                        try domains.append(self.allocator, try self.writer.addString(text));
                    }
                    for (contract.requires_functions) |requirement_node| {
                        const requirement = self.tree.contractFunctionRequirement(requirement_node) orelse continue;
                        const name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, requirement.name_token));
                        for (self.graph.semantic.parameterized_storage.contract_requirements.items[req_start..]) |previous| {
                            if (std.mem.eql(u8, self.graph.text(previous.name), self.graph.text(name)))
                                try self.contractError(requirement_node, "duplicate contract operation identity");
                        }
                        for (self.parameters.items) |binding| if (std.mem.eql(u8, binding.name, self.graph.text(name)))
                            try self.contractError(requirement_node, "contract operations and associated elements require distinct names");
                        const input = try self.lowerType(requirement.input, true);
                        const output = try self.lowerType(requirement.output, true);
                        const safety_contract = try self.lowerMethodSafetyContract(requirement, domains.items);
                        try self.graph.semantic.parameterized_storage.contract_requirements.append(self.allocator, .{
                            .source = .{ .file_index = self.sourceRef(requirement_node).file_index, .offset = self.tree.tokenLocation(requirement.name_token).offset },
                            .name = name,
                            .input = input,
                            .output = output,
                            .safety_contract = safety_contract,
                        });
                    }
                    try self.graph.semantic.parameterized_storage.contract_definitions.ensureUnusedCapacity(self.allocator, 1);
                    try self.writer.addContractDefinition(.{
                        .declaration = decl_id,
                        .parameters = params,
                        .participants = participants,
                        .composition = composition,
                        .requirements = .{
                            .start = req_start,
                            .len = @intCast(self.graph.semantic.parameterized_storage.contract_requirements.items.len - req_start),
                        },
                        .domains = try domains.toOwnedSlice(self.allocator),
                    });
                    stats.contract_definitions += 1;
                },
                else => {},
            }
        }
        return stats;
    }

    fn lowerMethodSafetyContract(self: *Context, requirement: syn.ContractFunctionRequirement, domains: []const primitives.StringRange) anyerror!?primitives.MethodSafetyContract {
        const node = requirement.safety_contract orelse return null;
        var general_conditions = false;
        var outcomes: std.ArrayList(primitives.MethodSafetyContract.Outcome) = .empty;
        defer outcomes.deinit(self.allocator);
        var dependencies: std.ArrayList(primitives.MethodSafetyContract.Dependency) = .empty;
        defer dependencies.deinit(self.allocator);
        var referents: std.ArrayList(primitives.MethodSafetyContract.Dependency) = .empty;
        defer referents.deinit(self.allocator);
        var owned_outputs: std.ArrayList(u32) = .empty;
        defer owned_outputs.deinit(self.allocator);
        var transfers: std.ArrayList(primitives.MethodSafetyContract.Dependency) = .empty;
        defer transfers.deinit(self.allocator);
        var relocations: std.ArrayList(primitives.MethodSafetyContract.Relocation) = .empty;
        defer relocations.deinit(self.allocator);
        var retained_inputs: std.ArrayList(primitives.MethodSafetyContract.Retention) = .empty;
        defer retained_inputs.deinit(self.allocator);
        var emptied_inputs: std.ArrayList(primitives.MethodSafetyContract.StorageInput) = .empty;
        defer emptied_inputs.deinit(self.allocator);
        var storage_sources: std.ArrayList(primitives.MethodSafetyContract.StorageDependency) = .empty;
        defer storage_sources.deinit(self.allocator);
        var consumed_inputs: std.ArrayList(u32) = .empty;
        defer consumed_inputs.deinit(self.allocator);
        var invalidates: std.ArrayList(u32) = .empty;
        defer invalidates.deinit(self.allocator);
        var domain_dependencies: std.ArrayList(primitives.MethodSafetyContract.DomainDependency) = .empty;
        defer domain_dependencies.deinit(self.allocator);
        var invalidated_domains: std.ArrayList(primitives.MethodSafetyContract.DomainInput) = .empty;
        defer invalidated_domains.deinit(self.allocator);
        if (self.tree.codeBlock(node)) |block| {
            for (block.statements) |statement| {
                if (self.tree.tag(statement) == .contract_outcome) {
                    const data = self.tree.extraData(syn.ContractOutcomeExtra, self.tree.data(statement).extra);
                    const output_name = self.tree.tokenTextFromSource(self.source, data.output);
                    var output_index: ?u32 = null;
                    for (self.tree.structTypeLiteral(requirement.output).?.fields, 0..) |field_node, index| {
                        const field = self.tree.structTypeField(field_node).?;
                        if (std.mem.eql(u8, output_name, self.tree.tokenTextFromSource(self.source, field.name_token))) output_index = @intCast(index);
                    }
                    var input_index: ?u32 = null;
                    if (output_index == null) for (self.tree.structTypeLiteral(requirement.input).?.fields, 0..) |field_node, index| {
                        const field = self.tree.structTypeField(field_node).?;
                        if (std.mem.eql(u8, output_name, self.tree.tokenTextFromSource(self.source, field.name_token))) input_index = @intCast(index);
                    };
                    if (output_index == null and input_index == null) {
                        try self.contractError(statement, "on must select a named method input or output");
                        unreachable;
                    }
                    if (input_index != null) general_conditions = true;
                    var child = requirement;
                    child.safety_contract = data.body;
                    const effect = (try self.lowerMethodSafetyContract(child, domains)).?;
                    if (effect.retained_inputs.len != 0) {
                        try self.contractError(statement, "conditional opaque storage clauses require correlated hidden storage post-states; declare unconditional effects instead");
                        unreachable;
                    }
                    if (effect.referents.len != 0 or effect.transfers.len != 0) {
                        try self.contractError(statement, "conditional refers_to and transfers require more precise outcome proofs");
                        unreachable;
                    }
                    general_conditions = general_conditions or effect.general_conditions;
                    for (effect.outcomes) |nested| {
                        if (nested.input_index != input_index or (input_index == null and nested.output_index != output_index.?)) general_conditions = true;
                    }
                    for (effect.dependencies) |dependency| if (output_index == null or dependency.output_index != output_index.?) {
                        general_conditions = true;
                    };
                    for (effect.domain_dependencies) |dependency| if (output_index == null or dependency.output_index != output_index.?) {
                        general_conditions = true;
                    };
                    for (effect.storage_sources) |source| if (output_index == null or source.output_index != output_index.?) {
                        general_conditions = true;
                    };
                    for (effect.owned_outputs) |owned| if (output_index == null or owned != output_index.?) {
                        general_conditions = true;
                    };
                    try outcomes.append(self.allocator, .{
                        .input_index = input_index,
                        .output_index = output_index orelse 0,
                        .variant = try self.writer.addString(self.tree.tokenTextFromSource(self.source, data.variant)),
                        .dependencies = effect.dependencies,
                        .domain_dependencies = effect.domain_dependencies,
                        .owned_outputs = effect.owned_outputs,
                        .storage_sources = effect.storage_sources,
                        .emptied_inputs = effect.emptied_inputs,
                        .consumed_inputs = effect.consumed_inputs,
                        .relocations = effect.relocations,
                        .invalidates = effect.invalidates,
                        .invalidated_domains = effect.invalidated_domains,
                        .outcomes = effect.outcomes,
                        .source = effect.source,
                    });
                    continue;
                }
                const clause = if (self.tree.tag(statement) == .expression_statement) self.tree.data(statement).node else statement;
                try self.lowerDependencyClause(requirement, clause, &dependencies, &referents, &invalidates, domains, &domain_dependencies, &invalidated_domains, &owned_outputs, &transfers, &consumed_inputs, &relocations, &retained_inputs, &emptied_inputs, &storage_sources);
            }
        } else try self.lowerDependencyClause(requirement, node, &dependencies, &referents, &invalidates, domains, &domain_dependencies, &invalidated_domains, &owned_outputs, &transfers, &consumed_inputs, &relocations, &retained_inputs, &emptied_inputs, &storage_sources);
        return .{
            .general_conditions = general_conditions,
            .outcomes = try outcomes.toOwnedSlice(self.allocator),
            .output_count = @intCast(self.tree.structTypeLiteral(requirement.output).?.fields.len),
            .dependencies = try dependencies.toOwnedSlice(self.allocator),
            .referents = try referents.toOwnedSlice(self.allocator),
            .consumed_inputs = try consumed_inputs.toOwnedSlice(self.allocator),
            .relocations = try relocations.toOwnedSlice(self.allocator),
            .retained_inputs = try retained_inputs.toOwnedSlice(self.allocator),
            .emptied_inputs = try emptied_inputs.toOwnedSlice(self.allocator),
            .storage_sources = try storage_sources.toOwnedSlice(self.allocator),
            .invalidates = try invalidates.toOwnedSlice(self.allocator),
            .domain_dependencies = try domain_dependencies.toOwnedSlice(self.allocator),
            .invalidated_domains = try invalidated_domains.toOwnedSlice(self.allocator),
            .owned_outputs = try owned_outputs.toOwnedSlice(self.allocator),
            .transfers = try transfers.toOwnedSlice(self.allocator),
            .source = self.sourceRef(node),
        };
    }

    fn contractError(self: *Context, node: syn.NodeIndex, message: []const u8) !void {
        if (self.diagnostics) |bag| try bag.add(self.tree.tokenLocation(self.tree.mainToken(node)), .semantic, "{s}", .{message});
        return error.Reported;
    }

    fn lowerDependencyClause(self: *Context, requirement: syn.ContractFunctionRequirement, node: syn.NodeIndex, dependencies: *std.ArrayList(primitives.MethodSafetyContract.Dependency), referents: *std.ArrayList(primitives.MethodSafetyContract.Dependency), invalidates: *std.ArrayList(u32), domains: []const primitives.StringRange, domain_dependencies: *std.ArrayList(primitives.MethodSafetyContract.DomainDependency), invalidated_domains: *std.ArrayList(primitives.MethodSafetyContract.DomainInput), owned_outputs: *std.ArrayList(u32), transfers: *std.ArrayList(primitives.MethodSafetyContract.Dependency), consumed_inputs: *std.ArrayList(u32), relocations: *std.ArrayList(primitives.MethodSafetyContract.Relocation), retained_inputs: *std.ArrayList(primitives.MethodSafetyContract.Retention), emptied_inputs: *std.ArrayList(primitives.MethodSafetyContract.StorageInput), storage_sources: *std.ArrayList(primitives.MethodSafetyContract.StorageDependency)) !void {
        const call = self.tree.functionCall(node) orelse return self.contractError(node, "expected depends_on, refers_to, owns, transfers, consumes, relocates, invalidates, retains, empties or from_storage in a safety contract");
        const name = self.tree.tokenTextFromSource(self.source, call.callee_token);
        if ((std.mem.eql(u8, name, "retains") or std.mem.eql(u8, name, "empties") or std.mem.eql(u8, name, "from_storage")) and call.module_qualifier == null and call.specialization_arguments == null) {
            const arguments = self.tree.structValueLiteral(call.input).?;
            const empty = std.mem.eql(u8, name, "empties");
            const from_storage = std.mem.eql(u8, name, "from_storage");
            if (from_storage) {
                if (arguments.fields.len < 2) return self.contractError(node, "from_storage requires an output followed by one or more storage inputs");
                var output_index: u32 = undefined;
                for (arguments.fields, 0..) |argument, index| {
                    const field = self.tree.valueField(argument).?;
                    if (field.name_token != null) return self.contractError(argument, "safety contract arguments must be positional names");
                    if (index == 0) {
                        output_index = (try self.contractFieldIndex(requirement.output, field.value)) orelse return self.contractError(field.value, "from_storage must name an output first");
                        continue;
                    }
                    const storage = try self.contractStorageInput(requirement, field.value, domains);
                    var duplicate = false;
                    for (storage_sources.items) |source| if (source.output_index == output_index and std.meta.eql(source.storage, storage)) {
                        duplicate = true;
                        break;
                    };
                    if (!duplicate) try storage_sources.append(self.allocator, .{ .output_index = output_index, .storage = storage });
                }
                return;
            }
            if (arguments.fields.len != (if (empty) @as(usize, 1) else 2)) return self.contractError(node, "empties requires one storage input; retains requires a storage input and a value input");
            for (arguments.fields) |argument| if (self.tree.valueField(argument).?.name_token != null) return self.contractError(argument, "safety contract arguments must be positional names");
            const storage = try self.contractStorageInput(requirement, self.tree.valueField(arguments.fields[0]).?.value, domains);
            if (empty) {
                for (emptied_inputs.items) |previous| if (std.meta.eql(previous, storage)) return;
                try emptied_inputs.append(self.allocator, storage);
            } else {
                const value_node = self.tree.valueField(arguments.fields[1]).?.value;
                const input = (try self.contractFieldIndex(requirement.input, value_node)) orelse return self.contractError(value_node, "retains must name a value input after its storage");
                if (storage.input_index == input) return self.contractError(node, "retains requires distinct storage and value inputs");
                for (retained_inputs.items) |retained| if (std.meta.eql(retained.storage, storage) and retained.input == input) return;
                try retained_inputs.append(self.allocator, .{ .storage = storage, .input = input });
            }
            return;
        }
        const is_referent = std.mem.eql(u8, name, "refers_to");
        if ((std.mem.eql(u8, name, "owns") or std.mem.eql(u8, name, "transfers")) and call.module_qualifier == null and call.specialization_arguments == null) {
            const arguments = self.tree.structValueLiteral(call.input).?;
            const owns = std.mem.eql(u8, name, "owns");
            if (arguments.fields.len != (if (owns) @as(usize, 1) else 2)) return self.contractError(node, "owns requires one output; transfers requires one output and one input");
            const output_field = self.tree.valueField(arguments.fields[0]).?;
            if (output_field.name_token != null) return self.contractError(node, "safety contract arguments must be positional names");
            const output_index = (try self.contractFieldIndex(requirement.output, output_field.value)) orelse return self.contractError(node, "ownership contracts must name a method output first");
            if (owns) {
                var found = false;
                for (owned_outputs.items) |existing| if (existing == output_index) {
                    found = true;
                    break;
                };
                if (!found) try owned_outputs.append(self.allocator, output_index);
            } else {
                const input_field = self.tree.valueField(arguments.fields[1]).?;
                if (input_field.name_token != null) return self.contractError(node, "safety contract arguments must be positional names");
                const input_index = (try self.contractFieldIndex(requirement.input, input_field.value)) orelse return self.contractError(node, "transfers must name a method input");
                try transfers.append(self.allocator, .{ .input_index = input_index, .output_index = output_index });
            }
            return;
        }

        if (std.mem.eql(u8, name, "relocates") and call.module_qualifier == null and call.specialization_arguments == null) {
            const arguments = self.tree.structValueLiteral(call.input).?;
            if (arguments.fields.len != 2) return self.contractError(node, "relocates requires a destination followed by a source input");
            var inputs: [2]u32 = undefined;
            for (arguments.fields, &inputs) |argument, *index| {
                const field = self.tree.valueField(argument).?;
                if (field.name_token != null) return self.contractError(argument, "safety contract arguments must be positional names");
                index.* = (try self.contractFieldIndex(requirement.input, field.value)) orelse return self.contractError(field.value, "relocates must name method inputs");
            }
            if (inputs[0] == inputs[1]) return self.contractError(node, "relocates requires distinct source and destination inputs");
            for (relocations.items) |previous| if (previous.destination == inputs[0] or previous.source == inputs[1] or previous.source == inputs[0] or previous.destination == inputs[1]) return self.contractError(node, "relocates inputs must belong to one disjoint transfer");
            try relocations.append(self.allocator, .{ .destination = inputs[0], .source = inputs[1] });
            return;
        }

        if (std.mem.eql(u8, name, "consumes") and call.module_qualifier == null and call.specialization_arguments == null) {
            const arguments = self.tree.structValueLiteral(call.input).?;
            if (arguments.fields.len == 0) return self.contractError(node, "consumes requires one or more mutable reference inputs");
            for (arguments.fields) |argument| {
                const field = self.tree.valueField(argument).?;
                if (field.name_token != null) return self.contractError(argument, "safety contract arguments must be positional names");
                const index = (try self.contractFieldIndex(requirement.input, field.value)) orelse
                    return self.contractError(field.value, "consumes must name a method input");
                if (std.mem.indexOfScalar(u32, consumed_inputs.items, index) == null) try consumed_inputs.append(self.allocator, index);
            }
            return;
        }

        if (std.mem.eql(u8, name, "invalidates") and call.module_qualifier == null and call.specialization_arguments == null) {
            const arguments = self.tree.structValueLiteral(call.input).?;
            if (arguments.fields.len == 0) return self.contractError(node, "invalidates requires one or more mutable reference inputs");
            for (arguments.fields) |argument| {
                const field = self.tree.valueField(argument).?;
                if (field.name_token != null) return self.contractError(argument, "safety contract arguments must be positional names");
                if (try self.contractDomainInput(requirement, field.value, domains)) |input| {
                    try invalidated_domains.append(self.allocator, input);
                    continue;
                }
                const index = (try self.contractFieldIndex(requirement.input, field.value)) orelse
                    return self.contractError(field.value, "invalidates must name a method input");
                var found = false;
                for (invalidates.items) |existing| if (existing == index) {
                    found = true;
                    break;
                };
                if (!found) try invalidates.append(self.allocator, index);
            }
            return;
        }
        if (call.module_qualifier != null or call.specialization_arguments != null or
            (!is_referent and !std.mem.eql(u8, name, "depends_on")))
            return self.contractError(node, "expected depends_on, refers_to, owns, transfers, consumes, relocates, invalidates, retains, empties or from_storage in a safety contract");
        const literal = self.tree.structValueLiteral(call.input).?;
        if (literal.fields.len < 2) return self.contractError(node, "depends_on requires an output followed by one or more inputs");
        if (is_referent and literal.fields.len != 2) return self.contractError(node, "refers_to requires exactly one output and one reference input");
        const output_node = self.tree.valueField(literal.fields[0]).?.value;
        const output_index = (try self.contractFieldIndex(requirement.output, output_node)) orelse
            return self.contractError(output_node, "the first depends_on argument must name a method output");
        for (literal.fields[1..]) |argument| {
            const field = self.tree.valueField(argument).?;
            if (field.name_token != null) return self.contractError(argument, "safety contract arguments must be positional names");
            if (try self.contractDomainInput(requirement, field.value, domains)) |input| {
                if (is_referent) return self.contractError(field.value, "refers_to names exact reference inputs; use depends_on for storage domains");
                try domain_dependencies.append(self.allocator, .{ .output_index = output_index, .input = input });
                continue;
            }
            const input_index = (try self.contractInputIndex(requirement, field.value)) orelse
                return self.contractError(field.value, "depends_on dependencies must name method inputs");
            const dependency = primitives.MethodSafetyContract.Dependency{ .output_index = output_index, .input_index = input_index };
            if (is_referent) {
                if (input_index >= self.tree.structTypeLiteral(requirement.input).?.fields.len)
                    return self.contractError(field.value, "refers_to requires an explicit reference input");
                for (referents.items) |item| {
                    if (item.output_index == output_index and item.input_index != input_index)
                        return self.contractError(node, "an output cannot have conflicting refers_to inputs");
                }
                var has_referent = false;
                for (referents.items) |item| if (item.output_index == output_index) {
                    has_referent = true;
                    break;
                };
                if (!has_referent) try referents.append(self.allocator, dependency);
            }
            var exists = false;
            for (dependencies.items) |item| if (item.output_index == output_index and item.input_index == input_index) {
                exists = true;
                break;
            };
            if (!exists) try dependencies.append(self.allocator, dependency);
        }
        if (self.tree.valueField(literal.fields[0]).?.name_token != null)
            return self.contractError(output_node, "safety contract arguments must be positional names");
    }

    fn contractStorageInput(self: *Context, requirement: syn.ContractFunctionRequirement, node: syn.NodeIndex, domains: []const primitives.StringRange) !primitives.MethodSafetyContract.StorageInput {
        if (try self.contractDomainInput(requirement, node, domains)) |domain| return .{ .input_index = domain.input_index, .domain_index = domain.domain_index };
        const index = (try self.contractFieldIndex(requirement.input, node)) orelse {
            try self.contractError(node, "opaque storage clauses must name a storage input or a participant domain");
            unreachable;
        };
        return .{ .input_index = index };
    }

    fn contractDomainInput(self: *Context, requirement: syn.ContractFunctionRequirement, node: syn.NodeIndex, domains: []const primitives.StringRange) !?primitives.MethodSafetyContract.DomainInput {
        const field = self.tree.structFieldAccess(node) orelse return null;
        const input = (try self.contractInputIndex(requirement, field.value)) orelse return self.contractDomainError(node, "storage domains must be rooted at a method input");
        const name = self.tree.tokenTextFromSource(self.source, field.field_token);
        for (domains, 0..) |domain, index| {
            if (std.mem.eql(u8, self.graph.text(domain), name)) return .{ .input_index = input, .domain_index = @intCast(index) };
        }
        return self.contractDomainError(node, "unknown Contract storage domain");
    }

    fn contractDomainError(self: *Context, node: syn.NodeIndex, message: []const u8) !?primitives.MethodSafetyContract.DomainInput {
        try self.contractError(node, message);
        unreachable;
    }

    fn contractInputIndex(self: *Context, requirement: syn.ContractFunctionRequirement, node: syn.NodeIndex) !?u32 {
        if (try self.contractFieldIndex(requirement.input, node)) |index| return index;
        const name = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
        if (!std.mem.eql(u8, name, "error_tracer")) return null;
        for (self.tree.structTypeLiteral(requirement.output).?.fields) |field_node| {
            const field = self.tree.structTypeField(field_node).?;
            const ty = self.tree.syntaxType(field.type_node orelse continue) orelse continue;
            const fallible = switch (ty) {
                .inferred_errable => true,
                .generic => |generic| blk: {
                    const base = self.tree.typeReference(generic.base) orelse break :blk false;
                    break :blk base == .name and std.mem.eql(u8, self.tree.tokenTextFromSource(self.source, base.name.name_token), "Errable");
                },
                else => false,
            };
            if (fallible) return @intCast(self.tree.structTypeLiteral(requirement.input).?.fields.len);
        }
        return null;
    }

    fn contractFieldIndex(self: *Context, signature: syn.NodeIndex, node: syn.NodeIndex) !?u32 {
        if (self.tree.tag(node) != .identifier) {
            try self.contractError(node, "safety contract arguments must name method inputs or outputs");
            unreachable;
        }
        const name = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
        for (self.tree.structTypeLiteral(signature).?.fields, 0..) |field_node, index| {
            const field = self.tree.structTypeField(field_node).?;
            if (field.position == null and std.mem.eql(u8, name, self.tree.tokenTextFromSource(self.source, field.name_token))) return @intCast(index);
        }
        return null;
    }

    const GenericTypePayload = struct {
        params: []const syn.NodeIndex,
        params_struct: ?syn.NodeIndex,
        value: syn.NodeIndex,
    };

    fn genericTypePayload(self: *Context, node: syn.NodeIndex) ?GenericTypePayload {
        const value = self.tree.typeDeclaration(node) orelse return null;
        return .{ .params = value.generic_params, .params_struct = value.generic_params_struct, .value = value.value };
    }

    fn lowerParameters(self: *Context, params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) !primitives.Range(ir.ComptimeParameterId) {
        const range = try self.registerParameters(params, params_struct);
        try self.lowerParameterBounds(range, params_struct);
        return range;
    }

    fn lowerParameterBounds(self: *Context, range: primitives.Range(ir.ComptimeParameterId), params_struct: ?syn.NodeIndex) !void {
        const struct_node = params_struct orelse return;
        const literal = self.tree.parameterList(struct_node) orelse return error.InvalidGenericParameters;
        const start = range.start;
        for (literal.fields, 0..) |field_node, offset| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
            const value_type_node = field.type_node orelse return error.InvalidGenericParameter;
            const parameter_record = &self.graph.semantic.parameterized_storage.comptime_parameters.items[
                start + @as(u32, @intCast(offset))
            ];
            switch (parameter_record.kind) {
                .comptime_int => parameter_record.value_type = try self.lowerType(value_type_node, false),
                .type => {
                    if (!isTypeBuiltin(self.tree, self.source, value_type_node))
                        parameter_record.constraint = try self.lowerContractConstraint(value_type_node);
                },
            }
            // Lower defaults after registering all parameters, keeping their
            // expressions symbolic until explicit/input bindings are known.
            if (field.default_value) |value| switch (parameter_record.kind) {
                .type => parameter_record.default_type = switch (try self.lowerGenericValue(value, false)) {
                    .type => |ty| ty,
                    else => return error.InvalidGenericArgumentKind,
                },
                .comptime_int => parameter_record.default_integer = try self.lowerIntExpression(value),
            };
        }
    }

    fn registerParameters(self: *Context, params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) !primitives.Range(ir.ComptimeParameterId) {
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len);
        if (params_struct) |struct_node| {
            const literal = self.tree.parameterList(struct_node) orelse return error.InvalidGenericParameters;

            // Register every parameter before lowering bounds. Bounds may refer
            // to associated parameters declared later in the same generic list,
            // e.g. t: Type: FalliblyCopyable#(.reasons: element_reasons).
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
                const name_text = self.tree.tokenTextFromSource(self.source, field.name_token);
                _ = field.type_node orelse return error.InvalidGenericParameter;
                const kind: parameterized_storage.ComptimeParameterKind =
                    if (isTypeParameter(self.tree, self.source, field)) .type else .comptime_int;
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = kind,
                });
                try self.parameters.append(.{ .name = name_text, .id = id, .kind = kind });
            }
        } else {
            for (params) |param_node| {
                const name_text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(param_node));
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = .type,
                });
                try self.parameters.append(.{ .name = name_text, .id = id, .kind = .type });
            }
        }
        return .{ .start = start, .len = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len - start) };
    }

    pub fn lowerContractConstraint(self: *Context, node: syn.NodeIndex) !parameterized_storage.ContractConstraintId {
        const syntax_type = self.tree.syntaxType(node) orelse return error.ExpectedContractType;
        var base_node = node;
        var arguments_node: ?syn.NodeIndex = null;
        switch (syntax_type) {
            .name => {},
            .generic => |generic| {
                base_node = generic.base;
                arguments_node = generic.arguments;
            },
            else => return error.ExpectedContractType,
        }

        const base = self.tree.syntaxType(base_node) orelse return error.ExpectedContractType;
        if (base != .name) return error.ExpectedContractType;
        const name = self.tree.tokenTextFromSource(self.source, base.name.name_token);
        const local_declaration =
            if (base.name.qualifier_token == null) self.localContractType(name) else null;
        const contract_ref: ir.DeclarationRef = if (local_declaration) |declaration|
            .{ .module = declaration }
        else
            .{ .external = try self.writer.addExternalRef(.{
                .kind = .contract,
                .module_path = if (base.name.qualifier_token) |qualifier|
                    try @import("../qualified_path.zig").intern(&self.writer, self.tree, self.source, qualifier, base.name.name_token)
                else
                    null,
                .name = try self.writer.addString(name),
                .source = self.sourceRef(base_node),
            }) };

        var arguments: std.ArrayList(ir.GenericArgument) = .empty;
        defer arguments.deinit(self.allocator);
        if (arguments_node) |args_node| {
            const literal = self.tree.specializationArguments(args_node) orelse return error.InvalidContractArguments;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidContractArgument;
                const value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                    .{ .type = try self.lowerType(type_node, false) }
                else if (field.default_value) |value_node|
                    try self.lowerGenericValue(value_node, false)
                else
                    return error.InvalidContractArgument;
                try arguments.append(self.allocator, .{
                    .name = try self.writer.addString(type_arguments.name(self.tree, self.source, field, "")),
                    .value = value,
                });
            }
        }

        const argument_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.generic_arguments.items.len);
        try self.graph.semantic.parameterized_storage.ir.generic_arguments.appendSlice(self.allocator, arguments.items);
        const id: parameterized_storage.ContractConstraintId =
            @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.contract_constraints.items.len)));
        try self.graph.semantic.parameterized_storage.contract_constraints.append(self.allocator, .{
            .contract_ref = contract_ref,
            .arguments = .{ .start = argument_start, .len = @intCast(arguments.items.len) },
            .source = self.sourceRef(node),
        });
        return id;
    }

    pub fn lowerType(self: *Context, node: syn.NodeIndex, allow_self: bool) anyerror!ir.ParameterizedTypeId {
        const syntax_type = self.tree.syntaxType(node) orelse return error.ExpectedParameterizedType;
        return switch (syntax_type) {
            .name => |name| self.lowerNamedType(node, name.name_token, name.qualifier_token, allow_self),
            .pointer => |value| blk: {
                const child = try self.lowerType(value.child, allow_self);
                break :blk try self.addType(.{ .resolved = .{ .pointer = .{ .child = child, .mutability = graph_mod.pointerMutabilityFromSyntax(value.mutability) } } });
            },
            .nullable => |child| try self.addType(.{ .resolved = .{ .nullable = try self.lowerType(child, allow_self) } }),
            .inferred_errable => |child| try self.addType(.{ .resolved = .{ .inferred_errable = try self.lowerType(child, allow_self) } }),
            .array => |value| blk: {
                const length = try self.lowerIntExpressionFromToken(value.length_token);
                const element = try self.lowerType(value.element, allow_self);
                break :blk try self.addType(.{ .array = .{ .length = length, .element = element, .source = self.sourceRef(node) } });
            },
            .generic => |value| self.lowerGenericType(value, allow_self),
            .projection => |value| self.addType(.{ .projection = .{
                .base = try self.lowerType(value.base, allow_self),
                .member = try self.writer.addString(self.tree.tokenTextFromSource(self.source, value.member_token)),
                .source = self.sourceRef(node),
            } }),
            .struct_literal => |literal| self.lowerStructDefinition(node, literal, allow_self),
            .choice_literal => |literal| self.lowerChoiceType(literal, allow_self),
        };
    }

    fn lowerNamedType(self: *Context, owner: syn.NodeIndex, name_token: syn.TokenIndex, qualifier: ?syn.TokenIndex, allow_self: bool) !ir.ParameterizedTypeId {
        const name = self.tree.tokenTextFromSource(self.source, name_token);
        if (allow_self and qualifier == null and std.mem.eql(u8, name, "Self")) {
            try self.contractError(owner, "use named participants instead of Self in this contract");
            unreachable;
        }
        if (qualifier == null) {
            if (self.parameter(name)) |binding| if (binding.kind == .type) return self.addType(.{ .parameter = binding.id });
            if (primitives.builtinTypeNamedForTarget(name, self.graph.target.stdTarget())) |builtin| {
                const concrete = try self.moduleBuiltin(builtin);
                return self.addType(.{ .concrete = concrete });
            }
            if (self.localType(name)) |local| {
                const ty = self.graph.declarations.items[@intFromEnum(local)].type_id orelse return error.TypeDeclarationWithoutType;
                return self.addType(.{ .concrete = ty });
            }
        }
        const external = try self.writer.addExternalRef(.{
            .kind = .type,
            .module_path = if (qualifier) |token_index| try @import("../qualified_path.zig").intern(&self.writer, self.tree, self.source, token_index, name_token) else null,
            .name = try self.writer.addString(name),
            .source = self.sourceRef(owner),
        });
        return self.addType(.{ .external = external });
    }

    fn lowerGenericType(self: *Context, generic: syn.GenericType, allow_self: bool) !ir.ParameterizedTypeId {
        if (type_lowerer.isRuntimeVirtualType(self.tree, self.source, generic)) {
            const literal = self.tree.specializationArguments(generic.arguments) orelse return error.InvalidVirtualArguments;
            if (literal.fields.len != 1) return error.InvalidVirtualArguments;
            const field = self.tree.structTypeField(literal.fields[0]) orelse return error.InvalidVirtualArguments;
            if (!type_arguments.isVirtualContractParameter(type_arguments.name(self.tree, self.source, field, "Virtual"))) return error.InvalidVirtualArguments;
            return self.addType(.{ .resolved = .{ .virtual = try self.lowerType(field.type_node orelse return error.InvalidVirtualArguments, allow_self) } });
        }
        const base = self.tree.typeReference(generic.base) orelse return error.InvalidGenericParameterizedBase;
        if (base != .name) return error.InvalidGenericParameterizedBase;
        const name = base.name;
        const base_text = self.tree.tokenTextFromSource(self.source, name.name_token);
        if (name.qualifier_token == null and std.mem.eql(u8, base_text, "choice_union")) {
            const literal = self.tree.specializationArguments(generic.arguments) orelse return error.InvalidChoiceUnionArguments;
            if (literal.fields.len != 2) return error.InvalidChoiceUnionArguments;
            var left: ?ir.ParameterizedTypeId = null;
            var right: ?ir.ParameterizedTypeId = null;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidChoiceUnionArguments;
                if (field.default_value != null) return error.InvalidChoiceUnionArguments;
                const ty = try self.lowerType(field.type_node orelse return error.InvalidChoiceUnionArguments, allow_self);
                const argument_name = type_arguments.name(self.tree, self.source, field, if (base.name.qualifier_token == null) base_text else "");
                if (std.mem.eql(u8, argument_name, "a") and left == null) left = ty else if (std.mem.eql(u8, argument_name, "b") and right == null) right = ty else return error.InvalidChoiceUnionArguments;
            }
            return self.addType(.{ .choice_union = .{ .left = left.?, .right = right.? } });
        }
        if (name.qualifier_token == null and std.mem.eql(u8, base_text, "Array")) {
            const literal = self.tree.specializationArguments(generic.arguments) orelse return error.InvalidArrayArguments;
            var length: ?ir.ParameterizedIntExprId = null;
            var element: ?ir.ParameterizedTypeId = null;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidArrayArguments;
                const argument_name = type_arguments.name(self.tree, self.source, field, if (base.name.qualifier_token == null) base_text else "");
                if (std.mem.eql(u8, argument_name, "n")) {
                    if (length != null or field.default_value == null) return error.InvalidArrayArguments;
                    length = try self.lowerIntExpression(field.default_value.?);
                } else if (std.mem.eql(u8, argument_name, "t")) {
                    if (element != null or field.type_node == null) return error.InvalidArrayArguments;
                    element = try self.lowerType(field.type_node.?, allow_self);
                } else return error.InvalidArrayArguments;
            }
            if (length == null or element == null) return error.InvalidArrayArguments;
            return self.addType(.{ .array = .{ .length = length.?, .element = element.?, .source = self.sourceRef(generic.base) } });
        }
        if (name.qualifier_token == null and std.mem.eql(u8, base_text, "Errable")) {
            const literal = self.tree.specializationArguments(generic.arguments) orelse return error.InvalidGenericParameterizedArguments;
            if (literal.fields.len == 1) {
                const field = self.tree.structTypeField(literal.fields[0]) orelse return error.InvalidGenericParameterizedArgument;
                if (std.mem.eql(u8, type_arguments.name(self.tree, self.source, field, "Errable"), "t")) {
                    const child = try self.lowerType(field.type_node orelse return error.InvalidGenericParameterizedArgument, allow_self);
                    return self.addType(.{ .resolved = .{ .inferred_errable = child } });
                }
            }
        }
        const declaration_ref = if (name.qualifier_token == null and self.localType(base_text) != null)
            ir.DeclarationRef{ .module = self.localType(base_text).? }
        else blk: {
            const external = try self.writer.addExternalRef(.{
                .kind = .type,
                .module_path = if (name.qualifier_token) |token_index| try @import("../qualified_path.zig").intern(&self.writer, self.tree, self.source, token_index, name.name_token) else null,
                .name = try self.writer.addString(base_text),
                .source = self.sourceRef(generic.base),
            });
            break :blk ir.DeclarationRef{ .external = external };
        };
        const parameterized_decl: ir.ParameterizedDeclId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.declarations.items.len)));
        try self.graph.semantic.parameterized_storage.ir.declarations.append(self.allocator, .{ .target = declaration_ref });

        const literal = self.tree.specializationArguments(generic.arguments) orelse return error.InvalidGenericParameterizedArguments;
        var arguments: std.ArrayList(ir.GenericArgument) = .empty;
        defer arguments.deinit(self.allocator);
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameterizedArgument;
            const name_range = try self.writer.addString(type_arguments.name(self.tree, self.source, field, if (base.name.qualifier_token == null) base_text else ""));
            const arg_value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                .{ .type = try self.lowerType(type_node, allow_self) }
            else if (field.default_value) |value_node|
                try self.lowerGenericValue(value_node, allow_self)
            else
                return error.InvalidGenericParameterizedArgument;
            try arguments.append(self.allocator, .{ .name = name_range, .value = arg_value });
        }
        const arg_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.generic_arguments.items.len);
        try self.graph.semantic.parameterized_storage.ir.generic_arguments.appendSlice(self.allocator, arguments.items);
        return self.addType(.{ .resolved = .{ .generic = .{
            .base = parameterized_decl,
            .arguments = .{ .start = arg_start, .len = @intCast(literal.fields.len) },
        } } });
    }

    fn lowerStructDefinition(self: *Context, node: syn.NodeIndex, literal: syn.StructTypeLiteral, allow_self: bool) !ir.ParameterizedTypeId {
        const origin = try self.writer.typeDefinitionAt(.{ .file_index = self.file_index, .offset = self.tree.location(node).offset });
        const body = try self.lowerStructType(literal, allow_self);
        var arguments: std.ArrayList(ir.GenericArgument) = .empty;
        defer arguments.deinit(self.allocator);
        for (self.parameters.items) |captured| try arguments.append(self.allocator, .{
            .name = try self.writer.addString(captured.name),
            .value = switch (captured.kind) {
                .type => .{ .type = try self.addType(.{ .parameter = captured.id }) },
                .comptime_int => .{ .comptime_int = try self.addInt(.{ .parameter = captured.id }) },
            },
        });
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.generic_arguments.items.len);
        try self.graph.semantic.parameterized_storage.ir.generic_arguments.appendSlice(self.allocator, arguments.items);
        return self.addType(.{ .definition = .{ .origin = origin, .body = body, .arguments = .{ .start = start, .len = @intCast(arguments.items.len) } } });
    }

    fn lowerStructType(self: *Context, literal: syn.StructTypeLiteral, allow_self: bool) !ir.ParameterizedTypeId {
        // Recursive types can append to the same pool. Publish immediate fields
        // together only after their children have been lowered.
        var fields: std.ArrayList(ir.Field) = .empty;
        defer fields.deinit(self.allocator);
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidParameterizedStructField;
            const type_node = field.type_node orelse return error.InvalidParameterizedStructField;
            try fields.append(self.allocator, .{
                .name = try self.writer.addString(if (field.inferred_result) "result" else self.tree.tokenTextFromSource(self.source, field.name_token)),
                .ty = try self.lowerType(type_node, allow_self),
                .source = self.sourceRef(field_node),
                .default_value = if (field.default_value) |value| try self.lowerBodyNode(value) else null,
            });
        }
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.fields.items.len);
        try self.graph.semantic.parameterized_storage.ir.fields.appendSlice(self.allocator, fields.items);
        return self.addType(.{ .resolved = .{ .structural = .{
            .fields = .{ .start = start, .len = @intCast(literal.fields.len) },
        } } });
    }

    pub fn lowerGenericValue(self: *Context, node: syn.NodeIndex, allow_self: bool) !ir.GenericArgument.Value {
        // A value argument uses integer projections; type arguments use lowerType.
        if (self.tree.tag(node) == .associated_type_projection) return .{ .comptime_int = try self.lowerIntExpression(node) };
        if (self.tree.tag(node) == .identifier) {
            const token = self.tree.mainToken(node);
            const name = self.tree.tokenTextFromSource(self.source, token);
            if (self.parameter(name)) |binding| {
                if (binding.kind == .type) return .{ .type = try self.addType(.{ .parameter = binding.id }) };
            } else if (primitives.builtinTypeNamedForTarget(name, self.graph.target.stdTarget()) != null or self.localType(name) != null) {
                return .{ .type = try self.lowerNamedType(node, token, null, allow_self) };
            }
        }
        if (self.tree.syntaxType(node) != null) return .{ .type = try self.lowerType(node, allow_self) };
        return .{ .comptime_int = try self.lowerIntExpression(node) };
    }

    fn lowerChoiceType(self: *Context, literal: syn.ChoiceTypeLiteral, allow_self: bool) !ir.ParameterizedTypeId {
        var variants: std.ArrayList(ir.Variant) = .empty;
        defer variants.deinit(self.allocator);
        for (literal.variants, 0..) |variant_node, index| {
            const variant = self.tree.choiceTypeVariant(variant_node) orelse return error.InvalidParameterizedChoiceVariant;
            try variants.append(self.allocator, .{ .semantic = .{
                .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, variant.name_token)),
                .payload_type = if (variant.payload_type) |payload| try self.lowerType(payload, allow_self) else null,
                .source = self.sourceRef(variant_node),
                .value = variant.value orelse @intCast(index),
            } });
        }
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.variants.items.len);
        try self.graph.semantic.parameterized_storage.ir.variants.appendSlice(self.allocator, variants.items);
        return self.addType(.{ .resolved = .{ .structural_choice = .{
            .variants = .{ .start = start, .len = @intCast(literal.variants.len) },
        } } });
    }

    fn lowerIntExpressionFromToken(self: *Context, token_index: syn.TokenIndex) !ir.ParameterizedIntExprId {
        const text = self.tree.tokenTextFromSource(self.source, token_index);
        if (self.parameter(text)) |binding| if (binding.kind == .comptime_int) {
            return self.addInt(.{ .parameter = binding.id });
        };
        const value = std.fmt.parseInt(i64, text, 0) catch return error.InvalidParameterizedComptimeInteger;
        return self.addInt(.{ .literal = value });
    }

    fn lowerAnonymousEntry(self: *Context, node: syn.NodeIndex) anyerror!ir.ParameterizedNodeId {
        const entry = self.tree.comptimeEntry(node).?;
        const input_kind = entry_interface.classifyInput(self.tree, self.source, entry.input, .isolated) catch {
            try self.contractError(node, entry_interface.comptime_input_message);
            unreachable;
        };
        const takes_system = input_kind == .system;
        // The same default syntax can be lowered in distinct semantic contexts;
        // source coordinates alone do not identify a generated declaration.
        const name_text = try std.fmt.allocPrint(self.allocator, "_comptime_entry_{d}_{d}_{d}", .{ self.file_index, self.sourceRef(node).offset, self.graph.declarations.items.len });
        defer self.allocator.free(name_text);
        const name = try self.writer.addString(name_text);
        const declaration: entities.ModuleDeclId = @enumFromInt(self.graph.declarations.items.len);
        try self.graph.declarations.append(self.allocator, .{
            .kind = .function,
            .name = name,
            .source_offset = self.sourceRef(node).offset,
            .module_file_index = self.file_index,
        });
        self.graph.generated_declaration_count += 1;
        var child = Context{
            .allocator = self.allocator,
            .graph = self.graph,
            .files = self.files,
            .writer = self.writer,
            .parameters = std.array_list.Managed(ParameterBinding).init(self.allocator),
            .bindings = std.array_list.Managed(BindingName).init(self.allocator),
            .file_index = self.file_index,
            .tree = self.tree,
            .source = self.source,
            .diagnostics = self.diagnostics,
            .inside_comptime_entry = true,
            .entry_parent = self,
        };
        defer child.entry_captures.deinit(self.allocator);
        defer child.parameters.deinit();
        defer child.bindings.deinit();
        try child.parameters.appendSlice(self.parameters.items);
        const empty = try child.addType(.{ .resolved = .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } } });
        const entry_input = if (entry.input) |syntax| try child.lowerType(syntax, false) else empty;
        const input_bindings: primitives.Range(ir.ParameterizedBindingId) = if (entry.input) |syntax| try child.seedFunctionBindings(syntax, .constant) else .{ .start = 0, .len = 0 };
        const output = if (entry.output) |syntax| try child.lowerType(syntax, false) else empty;
        const output_bindings: primitives.Range(ir.ParameterizedBindingId) = if (entry.output) |syntax| try child.seedFunctionBindings(syntax, .variable) else .{ .start = 0, .len = 0 };
        const body = try child.lowerBlock(entry.body);
        // Forward only the declaration-order prefix needed by the entry. In a
        // parameter default, forwarding the parameter being defined would turn
        // an otherwise closed entry into a dependency on its own result.
        // A captured binding's declared type can mention parameters without a
        // name lookup in the child. Retain that enclosing parameter environment.
        if (child.entry_captures.items.len != 0) child.referenced_parameter_prefix = self.parameters.items.len;
        const captured = self.parameters.items[0..child.referenced_parameter_prefix];
        self.referenced_parameter_prefix = @max(self.referenced_parameter_prefix, child.referenced_parameter_prefix);
        const parameters: primitives.Range(ir.ComptimeParameterId) = .{
            .start = if (captured.len == 0) 0 else @intFromEnum(captured[0].id),
            .len = @intCast(captured.len),
        };
        try self.writer.addParameterizedFunction(.{
            .is_comptime_entry = true,
            .declaration = declaration,
            .parameters = parameters,
            .input = entry_input,
            .input_bindings = input_bindings,
            .output = output,
            .body = body,
            .output_bindings = output_bindings,
        });
        var arguments: std.ArrayList(ir.GenericArgument) = .empty;
        defer arguments.deinit(self.allocator);
        for (captured) |parameter_binding| {
            try arguments.append(self.allocator, .{
                .name = try self.writer.addString(parameter_binding.name),
                .value = switch (parameter_binding.kind) {
                    .type => .{ .type = try self.addType(.{ .parameter = parameter_binding.id }) },
                    .comptime_int => .{ .comptime_int = try self.addInt(.{ .parameter = parameter_binding.id }) },
                },
            });
        }
        const argument_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.generic_arguments.items.len);
        try self.graph.semantic.parameterized_storage.ir.generic_arguments.appendSlice(self.allocator, arguments.items);
        const input = try self.addResolvedNode(node, empty, .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } });
        const call_name = if (takes_system) try child.lowerHostEntryWrapper(node, name, parameters, empty, output, output_bindings, .{ .start = argument_start, .len = @intCast(arguments.items.len) }) else name;
        const result = try self.addPending(node, .generic_call, &.{input}, call_name, null, .none);
        const pending = self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(result)].pending;
        self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending)].resolve_expression.comptime_run = !self.inside_comptime_entry;
        self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending)].resolve_expression.generic_arguments = .{ .start = argument_start, .len = @intCast(arguments.items.len) };
        return result;
    }

    fn lowerHostEntryWrapper(self: *Context, syntax: syn.NodeIndex, callee: primitives.StringRange, parameters: primitives.Range(ir.ComptimeParameterId), empty: ir.ParameterizedTypeId, output: ir.ParameterizedTypeId, original_outputs: primitives.Range(ir.ParameterizedBindingId), generic_arguments: primitives.Range(ir.ParameterizedGenericArgId)) !primitives.StringRange {
        const source = self.sourceRef(syntax);
        const spelling = try std.fmt.allocPrint(self.allocator, "_host{s}", .{self.graph.text(callee)});
        defer self.allocator.free(spelling);
        const name = try self.writer.addString(spelling);
        const declaration: entities.ModuleDeclId = @enumFromInt(self.graph.declarations.items.len);
        try self.graph.declarations.append(self.allocator, .{ .kind = .function, .name = name, .source_offset = source.offset, .module_file_index = self.file_index });
        self.graph.generated_declaration_count += 1;
        const text = entry_interface.bootstrap_source;
        var tree = try entry_interface.parseSystemScope(self.allocator);
        defer tree.deinit(self.allocator);
        var wrapper: Context = .{
            .allocator = self.allocator,
            .graph = self.graph,
            .files = self.files,
            .writer = self.writer,
            .parameters = std.array_list.Managed(ParameterBinding).init(self.allocator),
            .bindings = std.array_list.Managed(BindingName).init(self.allocator),
            .file_index = self.file_index,
            .tree = &tree,
            .source = text,
            .generated_source = source,
            .inside_comptime_entry = true,
        };
        defer wrapper.parameters.deinit();
        defer wrapper.bindings.deinit();
        defer wrapper.entry_captures.deinit(self.allocator);
        try wrapper.parameters.appendSlice(self.parameters.items);
        // Output defaults belong to the user body, not to its resource owner.
        const originals = try self.allocator.dupe(ir.Binding, self.graph.semantic.parameterized_storage.ir.bindings.items[original_outputs.start..][0..original_outputs.len]);
        defer self.allocator.free(originals);
        const output_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len);
        for (originals) |original| {
            var binding = original;
            binding.initialization = null;
            try self.graph.semantic.parameterized_storage.ir.bindings.append(self.allocator, binding);
        }
        const outputs: primitives.Range(ir.ParameterizedBindingId) = .{ .start = output_start, .len = original_outputs.len };
        const block = try wrapper.lowerBlock(tree.functionDeclaration(tree.roots[0]).?.body.?);
        const original_block = self.graph.semantic.parameterized_storage.ir.blocks.items[@intFromEnum(block)];
        var nodes: std.ArrayList(ir.ParameterizedNodeId) = .empty;
        defer nodes.deinit(self.allocator);
        try nodes.appendSlice(self.allocator, self.graph.semantic.parameterized_storage.ir.node_refs.items[original_block.nodes.start..][0..original_block.nodes.len]);
        var system: ?ir.ParameterizedBindingId = null;
        for (nodes.items) |id| {
            const node = self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(id)];
            if (node != .resolved or node.resolved.content != .binding_declaration) continue;
            const binding = node.resolved.content.binding_declaration;
            if (std.mem.eql(u8, self.graph.text(self.graph.semantic.parameterized_storage.ir.bindings.items[@intFromEnum(binding)].name), "system")) system = binding;
        }
        const system_binding = system orelse return error.MissingSystemEntryStorage;
        const system_value = try wrapper.addResolvedNode(syntax, self.graph.semantic.parameterized_storage.ir.bindingType(system_binding), .{ .binding_use = system_binding });
        const field_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.value_fields.items.len);
        try self.graph.semantic.parameterized_storage.ir.value_fields.append(self.allocator, .{ .name = try self.writer.addString("system"), .value = system_value });
        const input = try wrapper.addResolvedNode(syntax, null, .{ .struct_value_literal = .{ .fields = .{ .start = field_start, .len = 1 } } });
        const call_type = if (originals.len == 1) originals[0].ty else if (originals.len == 0) try wrapper.parameterizedBuiltin(.Void) else output;
        const call = try wrapper.addPending(syntax, .generic_call, &.{input}, callee, call_type, .none);
        const pending = self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(call)].pending;
        self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending)].resolve_expression.generic_arguments = generic_arguments;
        if (originals.len <= 1) {
            try nodes.append(self.allocator, if (originals.len == 1) try wrapper.addResolvedNode(syntax, originals[0].ty, .{ .assignment = .{ .binding = @enumFromInt(output_start), .value = call } }) else call);
        } else {
            const temporary: ir.ParameterizedBindingId = @enumFromInt(self.graph.semantic.parameterized_storage.ir.bindings.items.len);
            try self.graph.semantic.parameterized_storage.ir.bindings.append(self.allocator, .{ .name = try self.writer.addString("#entry_result"), .source = source, .ty = call_type, .initialization = call, .mutability = .constant });
            try nodes.append(self.allocator, try wrapper.addResolvedNode(syntax, null, .{ .binding_declaration = temporary }));
            const use = try wrapper.addResolvedNode(syntax, call_type, .{ .binding_use = temporary });
            for (originals, 0..) |binding, index| {
                const value = try wrapper.addPending(syntax, .field_access, &.{use}, binding.name, binding.ty, .none);
                try nodes.append(self.allocator, try wrapper.addResolvedNode(syntax, binding.ty, .{ .assignment = .{ .binding = @enumFromInt(output_start + @as(u32, @intCast(index))), .value = value } }));
            }
        }
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.node_refs.items.len);
        try self.graph.semantic.parameterized_storage.ir.node_refs.appendSlice(self.allocator, nodes.items);
        self.graph.semantic.parameterized_storage.ir.blocks.items[@intFromEnum(block)] = .{ .nodes = .{ .start = start, .len = @intCast(nodes.items.len) } };
        try self.writer.addParameterizedFunction(.{
            .is_comptime_entry = true,
            .is_comptime_host_entry = true,
            .declaration = declaration,
            .parameters = parameters,
            .input = empty,
            .output = output,
            .output_bindings = outputs,
            .body = block,
        });
        return name;
    }

    fn captureEntryValue(self: *Context, node: syn.NodeIndex, name: []const u8) anyerror!?ir.ParameterizedNodeId {
        for (self.entry_captures.items) |capture|
            if (std.mem.eql(u8, capture.name, name)) return capture.use_node;
        const use = if (self.entry_parent) |parent| blk: {
            const outer = if (parent.parameterizedBinding(name)) |binding|
                try parent.addResolvedNode(node, parent.graph.semantic.parameterized_storage.ir.bindingType(binding), .{ .binding_use = binding })
            else
                (try parent.captureEntryValue(node, name)) orelse return null;
            break :blk try self.addPending(node, .entry_capture, &.{outer}, try self.writer.addString(name), null, .none);
        } else if (self.module_capture_source) |source| blk: {
            const value = (try source.resolve(source.context, node, name)) orelse return null;
            const detail: ir.PendingExpressionDetail = switch (value) {
                .value => |value_node| .{ .capture_module_value = value_node },
                .owner => |owner| .{ .capture_owner = owner },
            };
            break :blk try self.addPending(node, .entry_capture, &.{}, try self.writer.addString(name), null, detail);
        } else return null;
        try self.entry_captures.append(self.allocator, .{ .name = name, .use_node = use });
        return use;
    }

    pub fn lowerIntExpression(self: *Context, node: syn.NodeIndex) anyerror!ir.ParameterizedIntExprId {
        if (self.tree.tag(node) == .comptime_entry)
            return self.addInt(.{ .execution = try self.lowerBodyNode(node) });
        if (self.tree.syntaxType(node)) |syntax| if (syntax == .projection) {
            return self.addInt(.{ .projection = .{
                .base = try self.lowerType(syntax.projection.base, false),
                .member = try self.writer.addString(self.tree.tokenTextFromSource(self.source, syntax.projection.member_token)),
                .source = self.sourceRef(node),
            } });
        };
        if (self.tree.literal(node)) |literal| {
            const text = self.tree.tokenTextFromSource(self.source, literal.token);
            var value = std.fmt.parseInt(i64, text, 0) catch return error.InvalidParameterizedComptimeInteger;
            if (literal.negative) value = -value;
            return self.addInt(.{ .literal = value });
        }
        if (self.tree.tag(node) == .identifier) {
            const name = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
            const binding = self.parameter(name) orelse return error.UnknownParameterizedComptimeParameter;
            if (binding.kind != .comptime_int) return error.ExpectedParameterizedComptimeParameter;
            return self.addInt(.{ .parameter = binding.id });
        }
        const op = self.tree.binaryOperation(node) orelse return error.InvalidParameterizedComptimeInteger;
        const operator: ir.IntBinaryOperator = switch (self.tree.tag(node)) {
            .binary_add => .add,
            .binary_subtract => .subtract,
            .binary_multiply => .multiply,
            .binary_divide => .divide,
            .binary_modulo => .modulo,
            else => return error.InvalidParameterizedComptimeInteger,
        };
        return self.addInt(.{ .binary = .{
            .operator = operator,
            .left = try self.lowerIntExpression(op.lhs),
            .right = try self.lowerIntExpression(op.rhs),
            .source = self.sourceRef(node),
        } });
    }

    fn seedFunctionBindings(self: *Context, struct_node: syn.NodeIndex, mutability: primitives.Mutability) !primitives.Range(ir.ParameterizedBindingId) {
        const literal = self.tree.structTypeLiteral(struct_node) orelse return .{ .start = 0, .len = 0 };
        var count: u32 = 0;
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse continue;
            if (field.type_node != null) count += 1;
        }
        // Defaults can lower nested functions with bindings of their own. Reserve
        // this interface's contiguous range before lowering any child expression.
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len);
        try self.graph.semantic.parameterized_storage.ir.bindings.appendNTimes(self.allocator, undefined, count);
        var offset: u32 = 0;
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse continue;
            const type_node = field.type_node orelse continue;
            const name = if (field.inferred_result) "result" else self.tree.tokenTextFromSource(self.source, field.name_token);
            const initialization = if (field.default_value) |value| try self.lowerBodyNode(value) else null;
            const binding_id: ir.ParameterizedBindingId = @enumFromInt(start + offset);
            const ty = try self.lowerType(type_node, false);
            const stored_name = try self.writer.addString(name);
            self.graph.semantic.parameterized_storage.ir.bindings.items[start + offset] = .{
                .name = stored_name,
                .source = self.sourceRef(field_node),
                .ty = ty,
                .initialization = initialization,
                .mutability = mutability,
            };
            try self.bindings.append(.{ .name = name, .id = binding_id });
            offset += 1;
        }
        return .{ .start = start, .len = count };
    }

    fn lowerBlock(self: *Context, node: syn.NodeIndex) anyerror!ir.ParameterizedBlockId {
        // Else-if syntax is a nested statement, but branch semantics use blocks.
        const source_statements = if (self.tree.codeBlock(node)) |block|
            block.statements
        else if (self.tree.ifStatement(node) != null)
            &.{node}
        else
            return error.ExpectedParameterizedBlock;
        const binding_mark = self.bindings.items.len;
        defer self.bindings.shrinkRetainingCapacity(binding_mark);
        var statements: std.ArrayList(ir.ParameterizedNodeId) = .empty;
        defer statements.deinit(self.allocator);
        var temporaries: std.ArrayList(ir.ParameterizedNodeId) = .empty;
        defer temporaries.deinit(self.allocator);
        const previous_temporaries = self.temporary_declarations;
        self.temporary_declarations = &temporaries;
        defer self.temporary_declarations = previous_temporaries;
        var ret_val: ?ir.ParameterizedNodeId = null;
        for (source_statements) |statement| {
            temporaries.clearRetainingCapacity();
            if (self.tree.tag(statement) == .assume_statement) {
                if (self.tree.assumedDeclaration(statement)) |declaration| {
                    const lowered = try self.lowerBodyNode(declaration);
                    try statements.appendSlice(self.allocator, temporaries.items);
                    try statements.append(self.allocator, lowered);
                    ret_val = lowered;
                }
                const name = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(statement));
                const binding = self.parameterizedBinding(name) orelse return error.UnknownAssumedVariable;
                try self.bindings.append(.{ .name = name, .id = binding, .assumed = true });
                continue;
            }
            const lowered = try self.lowerBodyNode(statement);
            try statements.appendSlice(self.allocator, temporaries.items);
            try statements.append(self.allocator, lowered);
            ret_val = lowered;
        }
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.node_refs.items.len);
        try self.graph.semantic.parameterized_storage.ir.node_refs.appendSlice(self.allocator, statements.items);
        const id: ir.ParameterizedBlockId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.blocks.items.len)));
        try self.graph.semantic.parameterized_storage.ir.blocks.append(self.allocator, .{
            .nodes = .{ .start = start, .len = @intCast(statements.items.len) },
            .ret_val = ret_val,
        });
        return id;
    }

    fn captureBindingCleanup(self: *Context, node: syn.NodeIndex, binding: ir.ParameterizedBindingId) !void {
        for (self.bindings.items) |visible| {
            if (!visible.assumed) continue;
            const input = try self.addResolvedNode(node, null, .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } });
            try self.captureAssumedFields(node, input);
            self.graph.semantic.parameterized_storage.ir.bindings.items[@intFromEnum(binding)].cleanup_arguments = input;
            break;
        }
    }

    fn captureAssumedFields(self: *Context, source: syn.NodeIndex, input: ir.ParameterizedNodeId) !void {
        var fields: std.ArrayList(ir.ValueField) = .empty;
        defer fields.deinit(self.allocator);
        for (self.bindings.items, 0..) |binding, index| {
            if (!binding.assumed) continue;
            var shadowed = false;
            for (self.bindings.items[index + 1 ..]) |later| {
                if (std.mem.eql(u8, binding.name, later.name)) {
                    shadowed = true;
                    break;
                }
            }
            if (shadowed) continue;
            const ty = self.graph.semantic.parameterized_storage.ir.bindingType(binding.id);
            const use = try self.addResolvedNode(source, ty, .{ .binding_use = binding.id });
            try fields.append(self.allocator, .{ .name = try self.writer.addString(binding.name), .value = use });
        }
        const storage = &self.graph.semantic.parameterized_storage.ir;
        const start: u32 = @intCast(storage.value_fields.items.len);
        try storage.value_fields.appendSlice(self.allocator, fields.items);
        storage.nodes.items[@intFromEnum(input)].resolved.content.struct_value_literal.assumed_fields = .{
            .start = start,
            .len = @intCast(fields.items.len),
        };
    }

    fn lowerBodyNode(self: *Context, node: syn.NodeIndex) anyerror!ir.ParameterizedNodeId {
        // A deferred action must complete without bypassing remaining defers
        // or automatic owner cleanup. Handle its failures locally instead.
        if (self.in_defer) switch (self.tree.tag(node)) {
            .return_statement, .error_propagation, .error_context, .error_report_return, .error_report_return_block => {
                if (self.diagnostics) |bag| try bag.add(self.tree.tokenLocation(self.tree.mainToken(node)), .semantic, "cannot return or propagate errors from a deferred action; use handle to process the error locally", .{});
                return error.Reported;
            },
            .break_statement, .continue_statement => if (self.defer_loop_depth == 0) {
                if (self.diagnostics) |bag| try bag.add(self.tree.tokenLocation(self.tree.mainToken(node)), .semantic, "cannot exit an enclosing loop from a deferred action", .{});
                return error.Reported;
            },
            else => {},
        };

        const previous_loop_depth = self.defer_loop_depth;
        if (self.in_defer and (self.tree.tag(node) == .while_statement or self.tree.forStatement(node) != null)) self.defer_loop_depth += 1;
        defer self.defer_loop_depth = previous_loop_depth;

        for (self.pipe_operand_overrides) |entry| if (entry.syntax == node) return entry.value;
        if (self.tree.tag(node) == .comptime_entry) return self.lowerAnonymousEntry(node);
        if (self.tree.tag(node) == .pipe_placeholder) return self.pipe_value orelse error.PipePlaceholderOutsidePipe;
        if (self.tree.tag(node) == .pipe_expression) return self.lowerPipe(node);
        if (self.tree.tag(node) == .handle_expression or self.tree.tag(node) == .error_report_return or self.tree.tag(node) == .error_report_return_block) return self.lowerHandle(node);
        if (self.tree.tag(node) == .expression_statement)
            return self.lowerBodyNode(self.tree.unaryOperand(node).?);
        if (self.tree.tag(node) == .reach_directive) return self.lowerReach(node);
        // Standalone blocks, including deferred handlers, already have a
        // resolved block representation; do not wrap them in an unknown op.
        if (self.tree.codeBlock(node) != null) return self.blockAsNode(node);
        if (self.tree.matchStatement(node)) |statement| {
            const value = try self.lowerBodyNode(statement.value);
            var cases: std.ArrayList(ir.MatchCase) = .empty;
            defer cases.deinit(self.allocator);
            for (statement.cases) |case_node| {
                const case = self.tree.matchCase(case_node) orelse return error.InvalidParameterizedMatchCase;
                const binding_mark = self.bindings.items.len;
                defer self.bindings.shrinkRetainingCapacity(binding_mark);
                const payload_binding: ?ir.ParameterizedBindingId = if (case.payload_name) |token| blk: {
                    const name = self.tree.tokenTextFromSource(self.source, token);
                    const binding: ir.ParameterizedBindingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len)));
                    try self.graph.semantic.parameterized_storage.ir.bindings.append(self.allocator, .{
                        .name = try self.writer.addString(name),
                        .source = self.sourceRef(case_node),
                        .ty = ir.unresolved_binding_type_poison,
                        .mutability = .constant,
                    });
                    try self.graph.semantic.parameterized_storage.ir.unresolved_binding_types.append(self.allocator, binding);
                    try self.captureBindingCleanup(case_node, binding);
                    try self.bindings.append(.{ .name = name, .id = binding });
                    break :blk binding;
                } else null;
                try cases.append(self.allocator, .{
                    .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, case.variant_token)),
                    .payload_binding = payload_binding,
                    .body = try self.lowerBlock(case.body),
                    .mode = graph_mod.matchCaseModeFromSyntax(case.mode),
                    .source = self.sourceRef(case_node),
                });
            }
            const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.match_cases.items.len);
            try self.graph.semantic.parameterized_storage.ir.match_cases.appendSlice(self.allocator, cases.items);
            const id = try self.addPending(node, .match, &.{value}, null, null, .none);
            const pending_id = self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(id)].pending;
            self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending_id)].resolve_expression.match_cases = .{ .start = start, .len = @intCast(cases.items.len) };
            return id;
        }
        if (self.tree.functionCall(node)) |call| {
            if (try @import("../../target_predicate.zig").evaluate(self.allocator, self.tree, self.source, node, self.graph.target, self.diagnostics)) |matched|
                return self.addResolvedNode(node, try self.parameterizedBuiltin(.Bool), .{ .bool_literal = matched });
            const input = try self.lowerBodyNode(call.input);
            try self.captureAssumedFields(node, input);
            var arguments: std.ArrayList(ir.GenericArgument) = .empty;
            defer arguments.deinit(self.allocator);
            if (call.specialization_arguments) |struct_node| {
                const literal = self.tree.specializationArguments(struct_node) orelse return error.InvalidParameterizedCallArguments;
                for (literal.fields) |field_node| {
                    const field = self.tree.structTypeField(field_node) orelse return error.InvalidParameterizedCallArgument;
                    const value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                        .{ .type = try self.lowerType(type_node, false) }
                    else if (field.default_value) |value_node|
                        try self.lowerGenericValue(value_node, false)
                    else
                        return error.InvalidParameterizedCallArgument;
                    try arguments.append(self.allocator, .{
                        .name = try self.writer.addString(type_arguments.name(self.tree, self.source, field, "")),
                        .value = value,
                    });
                }
            }
            const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.generic_arguments.items.len);
            try self.graph.semantic.parameterized_storage.ir.generic_arguments.appendSlice(self.allocator, arguments.items);
            const id = try self.addPending(node, .generic_call, &.{input}, try self.writer.addString(self.tree.tokenTextFromSource(self.source, call.callee_token)), null, .none);
            const pending_id = self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(id)].pending;
            self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending_id)].resolve_expression.generic_arguments = .{ .start = start, .len = @intCast(arguments.items.len) };
            self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending_id)].resolve_expression.module_path = if (call.module_qualifier) |token| try @import("../qualified_path.zig").intern(&self.writer, self.tree, self.source, token, call.callee_token) else null;
            if (call.contract_type) |contract| {
                const contract_type = try self.lowerType(contract, false);
                self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending_id)].resolve_expression.contract_type = contract_type;
            }
            return id;
        }
        if (self.tree.symbolDeclaration(node)) |declaration| {
            const initialization = if (declaration.value) |value| try self.lowerBodyNode(value) else null;
            const inferred_ty: ?ir.ParameterizedTypeId = if (initialization) |value|
                switch (self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(value)]) {
                    .resolved => |resolved_node| resolved_node.ty,
                    .pending => null,
                }
            else
                null;
            const ty: ?ir.ParameterizedTypeId = if (declaration.type_node) |value| try self.lowerType(value, false) else inferred_ty;
            if (initialization) |value| if (ty) |expected| {
                const storage = &self.graph.semantic.parameterized_storage.ir;
                if (storage.nodes.items[@intFromEnum(value)] == .pending) {
                    const pending_id = storage.nodes.items[@intFromEnum(value)].pending;
                    if (storage.pending.items[@intFromEnum(pending_id)] == .resolve_expression)
                        storage.pending.items[@intFromEnum(pending_id)].resolve_expression.expected_type = expected;
                }
            };
            const name = self.tree.tokenTextFromSource(self.source, declaration.name_token);
            const binding: ir.ParameterizedBindingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len)));
            try self.graph.semantic.parameterized_storage.ir.bindings.append(self.allocator, .{
                .name = try self.writer.addString(name),
                .source = self.sourceRef(node),
                .ty = ty orelse ir.unresolved_binding_type_poison,
                .initialization = initialization,
                .mutability = graph_mod.mutabilityFromSyntax(declaration.mutability),
            });
            try self.captureBindingCleanup(node, binding);
            if (ty == null) try self.graph.semantic.parameterized_storage.ir.unresolved_binding_types.append(self.allocator, binding);
            try self.bindings.append(.{ .name = name, .id = binding });
            return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .{ .binding_declaration = binding });
        }
        if (self.tree.assignment(node)) |assignment| {
            const name = self.tree.tokenTextFromSource(self.source, assignment.name_token);
            if (std.mem.eql(u8, name, "_")) return self.lowerBodyNode(assignment.value);
            const binding = self.parameterizedBinding(name) orelse {
                const target = try self.addPending(node, .unknown_identifier, &.{}, try self.writer.addString(name), null, .none);
                const address = try self.addPending(node, .address_of, &.{target}, null, null, .{ .pointer_mutability = .read_write });
                return self.addPending(node, .pointer_store, &.{ address, try self.lowerBodyNode(assignment.value) }, null, null, .none);
            };
            return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .{ .assignment = .{
                .binding = binding,
                .value = try self.lowerBodyNode(assignment.value),
            } });
        }
        if (self.tree.listLiteral(node)) |literal| {
            if (literal.elements.len == 0)
                return self.addResolvedNode(node, null, .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } });
        }
        if (self.tree.structValueLiteral(node)) |literal| {
            var fields: std.ArrayList(ir.ValueField) = .empty;
            defer fields.deinit(self.allocator);
            for (literal.fields) |field_node| {
                const field = self.tree.valueField(field_node) orelse return error.InvalidParameterizedValueField;
                try fields.append(self.allocator, .{
                    .name = try self.writer.addString(if (field.name_token) |token| self.tree.tokenTextFromSource(self.source, token) else ""),
                    .value = try self.lowerBodyNode(field.value),
                });
            }
            const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.value_fields.items.len);
            try self.graph.semantic.parameterized_storage.ir.value_fields.appendSlice(self.allocator, fields.items);
            return self.addResolvedNode(node, null, .{ .struct_value_literal = .{
                .fields = .{ .start = start, .len = @intCast(fields.items.len) },
                .dispatch_prefix_positional_count = literal.positional_prefix_count,
            } });
        }
        if (self.tree.choiceLiteral(node)) |literal| {
            const name = self.tree.tokenTextFromSource(self.source, literal.name_token);
            const payload = if (literal.payload) |child| try self.lowerBodyNode(child) else null;
            if (std.mem.eql(u8, name, "error")) if (payload) |payload_id| {
                const storage = &self.graph.semantic.parameterized_storage.ir;
                const payload_node = storage.nodes.items[@intFromEnum(payload_id)];
                if (payload_node == .resolved and payload_node.resolved.content == .struct_value_literal) {
                    const fields = payload_node.resolved.content.struct_value_literal.fields;
                    var has_reason = false;
                    var has_tracer = false;
                    for (storage.value_fields.items[fields.start..][0..fields.len]) |field| {
                        has_reason = has_reason or std.mem.eql(u8, self.graph.text(field.name), "reason");
                        has_tracer = has_tracer or std.mem.eql(u8, self.graph.text(field.name), "tracer");
                    }
                    if (has_reason and !has_tracer) {
                        const location = try self.syntheticErrorCall(node, "error_location_id", null);
                        const trace = try self.syntheticErrorCall(node, "capture_error_tracer", location);
                        const start: u32 = @intCast(storage.value_fields.items.len);
                        try storage.value_fields.ensureUnusedCapacity(self.allocator, fields.len + 1);
                        storage.value_fields.appendSliceAssumeCapacity(storage.value_fields.items[fields.start..][0..fields.len]);
                        try storage.value_fields.append(self.allocator, .{ .name = try self.writer.addString("tracer"), .value = trace });
                        storage.nodes.items[@intFromEnum(payload_id)].resolved.content.struct_value_literal.fields = .{ .start = start, .len = fields.len + 1 };
                    }
                }
            };
            return self.addPending(node, .choice_literal, if (payload) |id| &.{id} else &.{}, try self.writer.addString(name), null, .none);
        }
        // Keep the few parameter-independent leaves compact and represent every
        // semantic composition uniformly as a syntax-free pending expression.
        if (self.tree.literal(node)) |literal| {
            const token_content = self.tree.tokenContent(literal.token).literal;
            return switch (token_content) {
                .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => blk: {
                    const value = try literals.integerWithDiagnostic(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative, self.diagnostics, self.tree.tokenLocation(literal.token));
                    break :blk self.addResolvedNode(node, try self.parameterizedBuiltin(.Int32), .{ .int_literal = value });
                },
                .regular_float_literal, .scientific_float_literal => blk: {
                    const value = try literals.float(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative);
                    break :blk self.addResolvedNode(node, try self.parameterizedBuiltin(.Float32), .{ .float_literal = value });
                },
                .bool_literal => |value| self.addResolvedNode(node, try self.parameterizedBuiltin(.Bool), .{ .bool_literal = value }),
                .char_literal => |value| self.addResolvedNode(node, null, .{ .char_literal = value }),
                .string_literal => blk: {
                    const raw = self.tree.tokenTextFromSource(self.source, literal.token);
                    const decoded = try tok.decodeStringLiteral(self.allocator, raw);
                    defer if (std.mem.indexOfScalar(u8, raw, '\\') != null)
                        self.allocator.free(decoded);
                    break :blk self.addResolvedNode(node, null, .{
                        .string_literal = try self.writer.addString(decoded),
                    });
                },
            };
        }
        if (self.tree.tag(node) == .identifier) {
            const name = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
            if (self.parameterizedBinding(name)) |binding| {
                const ty = self.graph.semantic.parameterized_storage.ir.bindingType(binding);
                return self.addResolvedNode(node, ty, .{ .binding_use = binding });
            }
            if (try self.captureEntryValue(node, name)) |value| return value;
            if (self.parameter(name)) |parameter_binding| {
                switch (parameter_binding.kind) {
                    .type => {
                        const value = try self.addType(.{ .parameter = parameter_binding.id });
                        return self.addResolvedNode(node, try self.parameterizedBuiltin(.Type), .{ .type_literal = value });
                    },
                    .comptime_int => {
                        const parameter_record = self.graph.semantic.parameterized_storage.comptime_parameters.items[@intFromEnum(parameter_binding.id)];
                        return self.addPending(
                            node,
                            .comptime_parameter,
                            &.{},
                            null,
                            parameter_record.value_type,
                            .{ .comptime_parameter = parameter_binding.id },
                        );
                    },
                }
            }
            return self.addPending(node, .unknown_identifier, &.{}, try self.writer.addString(name), null, .none);
        }
        if (self.tree.forStatement(node)) |statement| {
            const iterable = try self.lowerBodyNode(statement.iterable);
            const name = self.tree.tokenTextFromSource(self.source, statement.name_token);
            const binding = try self.handleBinding(node, name, null);
            self.graph.semantic.parameterized_storage.ir.bindings.items[@intFromEnum(binding)].mutability = if (statement.mode == .mut_borrow) .variable else .constant;
            const mark = self.bindings.items.len;
            try self.bindings.append(.{ .name = name, .id = binding });
            defer self.bindings.shrinkRetainingCapacity(mark);
            const body = try self.lowerBlock(statement.body);
            const assumed = try self.addResolvedNode(node, null, .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } });
            try self.captureAssumedFields(node, assumed);
            const result = try self.addPending(node, .for_each, &.{iterable}, null, null, .{ .for_each = .{
                .binding = binding,
                .body = body,
                .mode = graph_mod.forModeFromSyntax(statement.mode),
            } });
            const pending_id = self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(result)].pending;
            self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending_id)].resolve_expression.assumed_arguments = assumed;
            return result;
        }
        if (self.tree.tag(node) == .break_statement)
            return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .break_statement);
        if (self.tree.tag(node) == .continue_statement)
            return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .continue_statement);
        if (self.tree.tag(node) == .abort_statement)
            return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .abort_statement);

        if (self.tree.addressOf(node)) |address| {
            if (self.tree.tag(address.value) == .pipe_placeholder) {
                return self.addPending(node, .address_of, &.{try self.lowerBodyNode(address.value)}, null, null, .{ .pipe_pointer_mutability = if (address.mutability == .read_write) .read_write else .read_only });
            }
            if (self.temporary_declarations) |temporaries| {
                if (!self.syntaxIsAddressable(address.value)) {
                    // Keep the reservation in the enclosing block and the
                    // initializer at the expression's evaluation point.
                    const initialized = try self.lowerBodyNode(address.value);
                    const storage = &self.graph.semantic.parameterized_storage.ir;
                    const ty: ?ir.ParameterizedTypeId = switch (storage.nodes.items[@intFromEnum(initialized)]) {
                        .resolved => |value| value.ty,
                        .pending => null,
                    };
                    const binding: ir.ParameterizedBindingId = @enumFromInt(@as(u32, @intCast(storage.bindings.items.len)));
                    try storage.bindings.append(self.allocator, .{
                        .name = try self.writer.addString("#address_temporary"),
                        .source = self.sourceRef(address.value),
                        .ty = ty orelse ir.unresolved_binding_type_poison,
                        .initialization = initialized,
                        .deferred_initialization = true,
                        .mutability = .variable,
                    });
                    try self.captureBindingCleanup(address.value, binding);
                    if (ty == null) try storage.unresolved_binding_types.append(self.allocator, binding);
                    const declaration = try self.addResolvedNode(address.value, try self.parameterizedBuiltin(.Void), .{ .binding_declaration = binding });
                    try temporaries.append(self.allocator, declaration);
                    const assignment = try self.addResolvedNode(address.value, ty, .{ .assignment = .{ .binding = binding, .value = initialized } });
                    return self.addPending(node, .address_of, &.{assignment}, null, null, parameterizedDetailForTag(self.tree.tag(node)));
                }
            }
        }

        const previous_defer = self.in_defer;
        if (self.tree.tag(node) == .defer_statement) {
            self.in_defer = true;
            self.defer_loop_depth = 0;
        }
        defer self.in_defer = previous_defer;

        var operands = std.array_list.Managed(ir.ParameterizedNodeId).init(self.allocator);
        defer operands.deinit();
        try self.collectBodyOperands(node, &operands);
        const kind: ir.PendingExpressionKind = if (self.tree.ifStatement(node)) |statement| if (statement.comptime_selection) .comptime_if else .if_statement else parameterizedKindForTag(self.tree.tag(node));
        const name = switch (self.tree.tag(node)) {
            .function_call => if (self.tree.functionCall(node)) |call| try self.writer.addString(self.tree.tokenTextFromSource(self.source, call.callee_token)) else null,
            .struct_field_access => if (self.tree.structFieldAccess(node)) |access| try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.field_token)) else null,
            .choice_payload_access => if (self.tree.choicePayloadAccess(node)) |access| try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.variant_token)) else null,
            .choice_literal, .choice_some_literal => if (self.tree.choiceLiteral(node)) |literal| try self.writer.addString(self.tree.tokenTextFromSource(self.source, literal.name_token)) else null,
            else => null,
        };
        // Specialization can select an operation with reached inputs even when
        // the operand types are not known yet. Retain lexical assume values.
        const assumed = if (kind == .binary or kind == .comparison) blk: {
            const input = try self.addResolvedNode(node, null, .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } });
            try self.captureAssumedFields(node, input);
            break :blk input;
        } else null;
        const result = try self.addPending(node, kind, operands.items, name, null, parameterizedDetailForTag(self.tree.tag(node)));
        const pending_id = self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(result)].pending;
        self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending_id)].resolve_expression.assumed_arguments = assumed;
        return result;
    }

    fn handleBinding(self: *Context, node: syn.NodeIndex, name: []const u8, initialization: ?ir.ParameterizedNodeId) !ir.ParameterizedBindingId {
        const storage = &self.graph.semantic.parameterized_storage.ir;
        const id: ir.ParameterizedBindingId = @enumFromInt(@as(u32, @intCast(storage.bindings.items.len)));
        try storage.bindings.append(self.allocator, .{
            .name = try self.writer.addString(name),
            .source = self.sourceRef(node),
            .ty = ir.unresolved_binding_type_poison,
            .initialization = initialization,
            .deferred_initialization = initialization != null,
            .mutability = .variable,
        });
        try storage.unresolved_binding_types.append(self.allocator, id);
        try self.captureBindingCleanup(node, id);
        return id;
    }

    fn handleBlock(self: *Context, nodes: []const ir.ParameterizedNodeId, result: ?ir.ParameterizedNodeId) !ir.ParameterizedBlockId {
        const storage = &self.graph.semantic.parameterized_storage.ir;
        const start: u32 = @intCast(storage.node_refs.items.len);
        try storage.node_refs.appendSlice(self.allocator, nodes);
        const id: ir.ParameterizedBlockId = @enumFromInt(@as(u32, @intCast(storage.blocks.items.len)));
        try storage.blocks.append(self.allocator, .{ .nodes = .{ .start = start, .len = @intCast(nodes.len) }, .ret_val = result });
        return id;
    }

    fn lowerHandle(self: *Context, node: syn.NodeIndex) !ir.ParameterizedNodeId {
        const reporting = self.tree.tag(node) == .error_report_return or self.tree.tag(node) == .error_report_return_block;
        const handle = if (reporting) syn.HandleExtra{ .value = self.tree.unaryOperand(node).?, .result_name = .none, .error_name = self.tree.mainToken(node), .body = node } else self.tree.extraData(syn.HandleExtra, self.tree.data(node).extra);
        const value = try self.lowerBodyNode(handle.value);
        const payload = try self.addPending(node, .choice_payload, &.{value}, try self.writer.addString("ok"), null, .none);
        const payload_pending = self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(payload)].pending;
        self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(payload_pending)].resolve_expression.requires_errable = true;
        if (!reporting and handle.result_name == .none) return self.lowerHandleWithoutResult(node, value);
        const result_name = if (reporting) "#reported_value" else self.tree.tokenTextFromSource(self.source, handle.result_name.unwrap().?);
        const error_name = if (reporting) "#reported_error" else self.tree.tokenTextFromSource(self.source, handle.error_name);
        if (std.mem.eql(u8, result_name, error_name)) {
            if (self.diagnostics) |bag| try bag.add(self.tree.tokenLocation(handle.error_name), .semantic, "handle result and error bindings must have different names", .{});
            return error.Reported;
        }
        const result = try self.handleBinding(node, result_name, payload);
        const temporaries = self.temporary_declarations orelse return error.HandleOutsideFunction;
        try temporaries.append(self.allocator, try self.addResolvedNode(node, null, .{ .binding_declaration = result }));
        const success = try self.handleBinding(node, "#handle_success", null);
        const failure = try self.handleBinding(node, error_name, null);
        const success_use = try self.addResolvedNode(node, null, .{ .binding_use = success });
        const moved = try self.addResolvedNode(node, null, .{ .move_value = success_use });
        const assignment = try self.addResolvedNode(node, null, .{ .assignment = .{ .binding = result, .value = moved } });
        const success_body = try self.handleBlock(&.{assignment}, null);
        const mark = self.bindings.items.len;
        try self.bindings.append(.{ .name = result_name, .id = result });
        try self.bindings.append(.{ .name = error_name, .id = failure });
        const failure_body = if (reporting) try self.lowerReportReturnBlock(node, failure) else try self.lowerBlock(handle.body);
        self.bindings.shrinkRetainingCapacity(mark);
        const storage = &self.graph.semantic.parameterized_storage.ir;
        const start: u32 = @intCast(storage.match_cases.items.len);
        for ([_][]const u8{ "ok", "error" }, [_]ir.ParameterizedBindingId{ success, failure }, [_]ir.ParameterizedBlockId{ success_body, failure_body }) |name, binding, body| {
            try storage.match_cases.append(self.allocator, .{ .name = try self.writer.addString(name), .payload_binding = binding, .body = body, .mode = .move, .source = self.sourceRef(node) });
        }
        const dispatch = try self.addPending(node, .match, &.{value}, null, null, .none);
        const pending = storage.nodes.items[@intFromEnum(dispatch)].pending;
        storage.pending.items[@intFromEnum(pending)].resolve_expression.match_cases = .{ .start = start, .len = 2 };
        const use = try self.addResolvedNode(node, null, .{ .binding_use = result });
        const result_move = try self.addResolvedNode(node, null, .{ .move_value = use });
        return self.addResolvedNode(node, null, .{ .value_sequence = try self.handleBlock(&.{ dispatch, result_move }, result_move) });
    }

    // Specialization retains the ordinary report call and containing return.
    fn lowerReportReturnBlock(self: *Context, node: syn.NodeIndex, failure: ir.ParameterizedBindingId) !ir.ParameterizedBlockId {
        const use = try self.addResolvedNode(node, null, .{ .binding_use = failure });
        const trace = try self.addPending(node, .field_access, &.{use}, try self.writer.addString("tracer"), null, .none);
        const storage = &self.graph.semantic.parameterized_storage.ir;
        const start: u32 = @intCast(storage.value_fields.items.len);
        try storage.value_fields.append(self.allocator, .{ .name = try self.writer.addString("tracer"), .value = trace });
        const input = try self.addResolvedNode(node, null, .{ .struct_value_literal = .{ .fields = .{ .start = start, .len = 1 } } });
        try self.captureAssumedFields(node, input);
        const report = try self.addPending(node, .generic_call, &.{input}, try self.writer.addString("report_trace"), null, .none);
        const ret = try self.addPending(node, .return_statement, &.{}, null, null, .none);
        if (self.tree.tag(node) == .error_report_return_block) {
            const action = try self.blockAsNode(self.tree.data(node).node_and_node.second);
            return self.handleBlock(&.{ report, action, ret }, null);
        }
        return self.handleBlock(&.{ report, ret }, null);
    }

    fn lowerHandleWithoutResult(self: *Context, node: syn.NodeIndex, value: ir.ParameterizedNodeId) !ir.ParameterizedNodeId {
        const handle = self.tree.extraData(syn.HandleExtra, self.tree.data(node).extra);
        const error_name = self.tree.tokenTextFromSource(self.source, handle.error_name);
        const success = try self.handleBinding(node, "#handle_success", null);
        const failure = try self.handleBinding(node, error_name, null);
        const success_body = try self.handleBlock(&.{}, null);
        const mark = self.bindings.items.len;
        try self.bindings.append(.{ .name = error_name, .id = failure });
        const failure_body = try self.lowerBlock(handle.body);
        self.bindings.shrinkRetainingCapacity(mark);
        const storage = &self.graph.semantic.parameterized_storage.ir;
        const start: u32 = @intCast(storage.match_cases.items.len);
        for ([_][]const u8{ "ok", "error" }, [_]ir.ParameterizedBindingId{ success, failure }, [_]ir.ParameterizedBlockId{ success_body, failure_body }) |name, binding, body| {
            try storage.match_cases.append(self.allocator, .{ .name = try self.writer.addString(name), .payload_binding = binding, .body = body, .mode = .move, .source = self.sourceRef(node) });
        }
        const dispatch = try self.addPending(node, .match, &.{value}, null, null, .none);
        const pending = storage.nodes.items[@intFromEnum(dispatch)].pending;
        storage.pending.items[@intFromEnum(pending)].resolve_expression.match_cases = .{ .start = start, .len = 2 };
        return self.addResolvedNode(node, null, .{ .value_sequence = try self.handleBlock(&.{dispatch}, dispatch) });
    }

    fn lowerPipe(self: *Context, node: syn.NodeIndex) !ir.ParameterizedNodeId {
        const op = self.tree.binaryOperation(node).?;
        var evaluations: std.ArrayList(ir.ParameterizedNodeId) = .empty;
        defer evaluations.deinit(self.allocator);
        const lhs = try self.lowerPipeOperand(op.lhs, &evaluations);
        const previous = self.pipe_value;
        self.pipe_value = lhs;
        defer self.pipe_value = previous;
        const rhs = try self.lowerBodyNode(op.rhs);
        if (evaluations.items.len == 0) return rhs;
        try evaluations.append(self.allocator, rhs);
        const storage = &self.graph.semantic.parameterized_storage.ir;
        const start: u32 = @intCast(storage.node_refs.items.len);
        try storage.node_refs.appendSlice(self.allocator, evaluations.items);
        const block: ir.ParameterizedBlockId = @enumFromInt(@as(u32, @intCast(storage.blocks.items.len)));
        try storage.blocks.append(self.allocator, .{ .nodes = .{ .start = start, .len = @intCast(evaluations.items.len) }, .ret_val = rhs });
        return self.addResolvedNode(node, null, .{ .value_sequence = block });
    }

    // Retain the same storage/evaluation split as concrete body lowering;
    // specialization supplies types without changing placeholder identity.
    fn lowerPipeOperand(self: *Context, node: syn.NodeIndex, evaluations: *std.ArrayList(ir.ParameterizedNodeId)) anyerror!ir.ParameterizedNodeId {
        switch (self.tree.tag(node)) {
            .identifier, .pipe_placeholder, .literal => return self.lowerBodyNode(node),
            .struct_field_access, .choice_payload_access, .dereference, .index_access => {
                const base_node = switch (self.tree.tag(node)) {
                    .struct_field_access => self.tree.structFieldAccess(node).?.value,
                    .choice_payload_access => self.tree.choicePayloadAccess(node).?.value,
                    .dereference => self.tree.unaryOperand(node).?,
                    .index_access => self.tree.binaryOperation(node).?.lhs,
                    else => unreachable,
                };
                const base = try self.lowerPipeOperand(base_node, evaluations);
                var entries: [2]PipeOperandOverride = undefined;
                entries[0] = .{ .syntax = base_node, .value = base };
                var count: usize = 1;
                if (self.tree.tag(node) == .index_access) {
                    const index_node = self.tree.binaryOperation(node).?.rhs;
                    entries[1] = .{ .syntax = index_node, .value = try self.cachePipeValue(index_node, try self.lowerBodyNode(index_node), evaluations) };
                    count = 2;
                }
                const previous = self.pipe_operand_overrides;
                self.pipe_operand_overrides = entries[0..count];
                defer self.pipe_operand_overrides = previous;
                return self.lowerBodyNode(node);
            },
            else => return self.cachePipeValue(node, try self.lowerBodyNode(node), evaluations),
        }
    }

    fn cachePipeValue(self: *Context, node: syn.NodeIndex, value: ir.ParameterizedNodeId, evaluations: *std.ArrayList(ir.ParameterizedNodeId)) !ir.ParameterizedNodeId {
        if (self.tree.tag(node) == .literal) return value;
        const temporaries = self.temporary_declarations orelse return value;
        const storage = &self.graph.semantic.parameterized_storage.ir;
        const ty: ?ir.ParameterizedTypeId = switch (storage.nodes.items[@intFromEnum(value)]) {
            .resolved => |item| item.ty,
            .pending => null,
        };
        const binding: ir.ParameterizedBindingId = @enumFromInt(@as(u32, @intCast(storage.bindings.items.len)));
        try storage.bindings.append(self.allocator, .{
            .name = try self.writer.addString("#pipe_temporary"),
            .source = self.sourceRef(node),
            .ty = ty orelse ir.unresolved_binding_type_poison,
            .initialization = value,
            .deferred_initialization = true,
            .mutability = .variable,
        });
        if (ty == null) try storage.unresolved_binding_types.append(self.allocator, binding);
        try self.captureBindingCleanup(node, binding);
        try temporaries.append(self.allocator, try self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .{ .binding_declaration = binding }));
        try evaluations.append(self.allocator, try self.addResolvedNode(node, ty, .{ .assignment = .{ .binding = binding, .value = value } }));
        return self.addResolvedNode(node, ty, .{ .binding_use = binding });
    }

    fn syntheticErrorCall(self: *Context, node: syn.NodeIndex, name: []const u8, location: ?ir.ParameterizedNodeId) !ir.ParameterizedNodeId {
        const storage = &self.graph.semantic.parameterized_storage.ir;
        const start: u32 = @intCast(storage.value_fields.items.len);
        if (location) |value| try storage.value_fields.append(self.allocator, .{ .name = try self.writer.addString("location"), .value = value });
        const input = try self.addResolvedNode(node, null, .{ .struct_value_literal = .{ .fields = .{ .start = start, .len = if (location != null) 1 else 0 } } });
        try self.captureAssumedFields(node, input);
        return self.addPending(node, .generic_call, &.{input}, try self.writer.addString(name), null, .none);
    }

    fn syntaxIsAddressable(self: *const Context, node: syn.NodeIndex) bool {
        return switch (self.tree.tag(node)) {
            .identifier, .pipe_placeholder, .dereference => true,
            .struct_field_access => self.syntaxIsAddressable(self.tree.structFieldAccess(node).?.value),
            .choice_payload_access => self.syntaxIsAddressable(self.tree.choicePayloadAccess(node).?.value),
            .index_access => self.syntaxIsAddressable(self.tree.indexAccess(node).?.value),
            else => false,
        };
    }

    fn lowerReach(self: *Context, node: syn.NodeIndex) !ir.ParameterizedNodeId {
        const directive = self.tree.reachDirective(node) orelse return error.InvalidParameterizedReach;
        const alt_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.reach_alternatives.items.len);
        for (directive.alternatives) |alt_node| {
            const alternative = self.tree.reachAlternative(alt_node) orelse return error.InvalidParameterizedReachAlternative;
            const segment_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.reach_segments.items.len);
            for (alternative.segments) |segment| {
                try self.graph.semantic.parameterized_storage.ir.reach_segments.append(self.allocator, try self.writer.addString(self.tree.tokenTextFromSource(self.source, self.tree.mainToken(segment))));
            }
            try self.graph.semantic.parameterized_storage.ir.reach_alternatives.append(self.allocator, .{
                .segments = .{ .start = segment_start, .len = @intCast(alternative.segments.len) },
            });
        }
        const reach_id: ir.ParameterizedReachId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.reaches.items.len)));
        try self.graph.semantic.parameterized_storage.ir.reaches.append(self.allocator, .{
            .alternatives = .{ .start = alt_start, .len = @intCast(directive.alternatives.len) },
        });
        return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .{ .reach_directive = reach_id });
    }

    fn collectBodyOperands(self: *Context, node: syn.NodeIndex, result: *std.array_list.Managed(ir.ParameterizedNodeId)) anyerror!void {
        if (self.tree.pointerAssignment(node)) |assignment| {
            const pointer = if (self.tree.tag(assignment.target) == .dereference)
                self.tree.unaryOperand(assignment.target).?
            else
                assignment.target;
            const target = try self.lowerBodyNode(pointer);
            try result.append(if (self.tree.tag(assignment.target) == .dereference)
                target
            else
                try self.addPending(node, .address_of, &.{target}, null, null, .{ .pointer_mutability = .read_write }));
            try result.append(try self.lowerBodyNode(assignment.value));
            return;
        }
        if (self.tree.indexAssignment(node)) |assignment| {
            const target = self.tree.indexAccess(assignment.target) orelse return error.InvalidIndexAssignmentTarget;
            try result.append(try self.lowerBodyNode(target.value));
            try result.append(try self.lowerBodyNode(target.index));
            try result.append(try self.lowerBodyNode(assignment.value));
            return;
        }
        if (self.tree.indexAccess(node)) |access| {
            try result.append(try self.lowerBodyNode(access.value));
            try result.append(try self.lowerBodyNode(access.index));
            return;
        }
        if (self.tree.structFieldAccess(node)) |access| {
            try result.append(try self.lowerBodyNode(access.value));
            return;
        }
        if (self.tree.choicePayloadAccess(node)) |access| {
            try result.append(try self.lowerBodyNode(access.value));
            return;
        }
        if (self.tree.binaryOperation(node)) |operation| {
            try result.append(try self.lowerBodyNode(operation.lhs));
            try result.append(try self.lowerBodyNode(operation.rhs));
            return;
        }
        if (self.tree.unaryOperand(node)) |operand| {
            try result.append(try self.lowerBodyNode(operand));
            return;
        }
        if (self.tree.functionCall(node)) |call| {
            try result.append(try self.lowerBodyNode(call.input));
            return;
        }
        if (self.tree.ifStatement(node)) |statement| {
            try result.append(try self.lowerBodyNode(statement.condition));
            try result.append(try self.blockAsNode(statement.then_block));
            if (statement.else_block) |else_block| try result.append(try self.blockAsNode(else_block));
            return;
        }
        if (self.tree.whileStatement(node)) |statement| {
            try result.append(try self.lowerBodyNode(statement.condition));
            try result.append(try self.blockAsNode(statement.body));
            return;
        }
        if (self.tree.forStatement(node)) |statement| {
            try result.append(try self.lowerBodyNode(statement.iterable));
            try result.append(try self.blockAsNode(statement.body));
            return;
        }
        if (self.tree.matchStatement(node)) |statement| {
            try result.append(try self.lowerBodyNode(statement.value));
            for (statement.cases) |case_node| {
                const case = self.tree.matchCase(case_node) orelse continue;
                try result.append(try self.blockAsNode(case.body));
            }
            return;
        }
        if (self.tree.codeBlock(node) != null) {
            try result.append(try self.blockAsNode(node));
            return;
        }
        if (self.tree.structValueLiteral(node)) |literal| {
            for (literal.fields) |field_node| if (self.tree.valueField(field_node)) |field|
                try result.append(try self.lowerBodyNode(field.value));
            return;
        }
        if (self.tree.listLiteral(node)) |literal| {
            for (literal.elements) |element| try result.append(try self.lowerBodyNode(element));
            return;
        }
        if (self.tree.choiceLiteral(node)) |literal| if (literal.payload) |payload|
            try result.append(try self.lowerBodyNode(payload));
        if (self.tree.returnStatement(node)) |statement| if (statement.value) |value|
            try result.append(try self.lowerBodyNode(value));
    }

    fn blockAsNode(self: *Context, node: syn.NodeIndex) !ir.ParameterizedNodeId {
        const block = try self.lowerBlock(node);
        const body = self.graph.semantic.parameterized_storage.ir.blocks.items[@intFromEnum(block)];
        const ty: ?ir.ParameterizedTypeId = if (body.ret_val) |ret_val|
            switch (self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(ret_val)]) {
                .resolved => |resolved_node| resolved_node.ty,
                .pending => null,
            }
        else
            try self.parameterizedBuiltin(.Void);
        return self.addResolvedNode(node, ty, .{ .code_block = block });
    }

    fn addPending(self: *Context, node: syn.NodeIndex, kind: ir.PendingExpressionKind, operands: []const ir.ParameterizedNodeId, name: ?primitives.StringRange, expected: ?ir.ParameterizedTypeId, detail: ir.PendingExpressionDetail) !ir.ParameterizedNodeId {
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.node_refs.items.len);
        try self.graph.semantic.parameterized_storage.ir.node_refs.appendSlice(self.allocator, operands);
        const pending_id: ir.ParameterizedPendingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.pending.items.len)));
        try self.graph.semantic.parameterized_storage.ir.pending.append(self.allocator, .{ .resolve_expression = .{
            .kind = kind,
            .operands = .{ .start = start, .len = @intCast(operands.len) },
            .name = name,
            .expected_type = expected,
            .source = self.sourceRef(node),
            .detail = detail,
        } });
        const id: ir.ParameterizedNodeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.nodes.items.len)));
        try self.graph.semantic.parameterized_storage.ir.nodes.append(self.allocator, .{ .pending = pending_id });
        return id;
    }

    fn addResolvedNode(self: *Context, node: syn.NodeIndex, ty: ?ir.ParameterizedTypeId, content: ir.ResolvedNode.Content) !ir.ParameterizedNodeId {
        const id: ir.ParameterizedNodeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.nodes.items.len)));
        try self.graph.semantic.parameterized_storage.ir.nodes.append(self.allocator, .{ .resolved = .{
            .source = self.sourceRef(node),
            .ty = ty,
            .content = content,
        } });
        return id;
    }

    fn addType(self: *Context, value: ir.Type) !ir.ParameterizedTypeId {
        const id: ir.ParameterizedTypeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.types.items.len)));
        try self.graph.semantic.parameterized_storage.ir.types.append(self.allocator, value);
        return id;
    }

    fn addInt(self: *Context, value: ir.IntExpression) !ir.ParameterizedIntExprId {
        const id: ir.ParameterizedIntExprId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.int_expressions.items.len)));
        try self.graph.semantic.parameterized_storage.ir.int_expressions.append(self.allocator, value);
        return id;
    }

    fn parameterizedBuiltin(self: *Context, builtin: primitives.BuiltinType) !ir.ParameterizedTypeId {
        return self.addType(.{ .concrete = try self.moduleBuiltin(builtin) });
    }

    fn moduleBuiltin(self: *Context, builtin: primitives.BuiltinType) !entities.ModuleTypeId {
        for (0..views.typeCount(self.graph)) |raw| {
            const id: entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw)));
            switch (try views.typeView(self.graph, id)) {
                .resolved => |resolved| switch (resolved) {
                    .builtin => |value| if (value == builtin) return id,
                    else => {},
                },
                .external => {},
            }
        }
        return self.writer.addResolvedType(.{ .builtin = builtin });
    }

    fn parameter(self: *Context, name: []const u8) ?ParameterBinding {
        var i = self.parameters.items.len;
        while (i != 0) {
            i -= 1;
            if (std.mem.eql(u8, self.parameters.items[i].name, name)) {
                self.referenced_parameter_prefix = @max(self.referenced_parameter_prefix, i + 1);
                return self.parameters.items[i];
            }
        }
        return null;
    }

    fn parameterizedBinding(self: *Context, name: []const u8) ?ir.ParameterizedBindingId {
        var i = self.bindings.items.len;
        while (i != 0) {
            i -= 1;
            if (std.mem.eql(u8, self.bindings.items[i].name, name)) return self.bindings.items[i].id;
        }
        return null;
    }

    fn localType(self: *Context, name: []const u8) ?entities.ModuleDeclId {
        for (self.graph.declarationsNamed(name)) |id| switch (self.graph.declarations.items[@intFromEnum(id)].kind) {
            .type, .contract_type => return id,
            else => {},
        };
        return null;
    }

    fn localContractType(self: *Context, name: []const u8) ?entities.ModuleDeclId {
        for (self.graph.declarationsNamed(name)) |id|
            if (self.graph.declarations.items[@intFromEnum(id)].kind == .contract_type) return id;
        return null;
    }

    fn sourceRef(self: *Context, node: syn.NodeIndex) primitives.SourceRef {
        return self.generated_source orelse .{ .file_index = self.file_index, .offset = self.tree.location(node).offset };
    }
};

fn hasGenericParameters(params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) bool {
    return params.len != 0 or params_struct != null;
}

fn isTypeBuiltin(tree: *const syn.FileSyntaxTree, source: []const u8, node: syn.NodeIndex) bool {
    const ty = tree.syntaxType(node) orelse return false;
    if (ty != .name or ty.name.qualifier_token != null) return false;
    return std.mem.eql(u8, tree.tokenTextFromSource(source, ty.name.name_token), "Type");
}

pub fn isTypeParameter(tree: *const syn.FileSyntaxTree, source: []const u8, field: syn.StructTypeField) bool {
    const type_node = field.type_node orelse return true;
    if (isTypeBuiltin(tree, source, type_node)) return true;

    // Syntaxing validates constrained parameters as `.name: Type: Bound` but
    // stores only `Bound` as the field type. Preserve that distinction from a
    // normal comptime parameter by observing the two validated separators.
    const name_location = tree.tokenLocation(field.name_token);
    const type_location = tree.location(type_node);
    const start = name_location.offset + tree.tokenTextFromSource(source, field.name_token).len;
    if (start > type_location.offset or type_location.offset > source.len) return false;
    return std.mem.count(u8, source[start..type_location.offset], ":") >= 2;
}

fn parameterizedDetailForTag(tag: syn.Node.Tag) ir.PendingExpressionDetail {
    return switch (tag) {
        .binary_add => .{ .binary = .addition },
        .binary_subtract => .{ .binary = .subtraction },
        .binary_multiply => .{ .binary = .multiplication },
        .binary_divide => .{ .binary = .division },
        .binary_modulo => .{ .binary = .modulo },
        .compare_equal => .{ .comparison = .equal },
        .compare_not_equal => .{ .comparison = .not_equal },
        .compare_less => .{ .comparison = .less_than },
        .compare_greater => .{ .comparison = .greater_than },
        .compare_less_equal => .{ .comparison = .less_than_or_equal },
        .compare_greater_equal => .{ .comparison = .greater_than_or_equal },
        .logical_and => .{ .logical = .and_ },
        .logical_or => .{ .logical = .or_ },
        .address_of => .{ .pointer_mutability = .read_only },
        .address_of_mut => .{ .pointer_mutability = .read_write },
        else => .none,
    };
}

fn parameterizedKindForTag(tag: syn.Node.Tag) ir.PendingExpressionKind {
    return switch (tag) {
        .pipe_expression => .pipe,
        .unwrap_or => .unwrap_or,
        .unwrap_or_do => .unwrap_or_do,
        .nullable_test => .nullable_test,
        .function_call => .generic_call,
        .choice_literal, .choice_some_literal => .choice_literal,
        .struct_field_access => .field_access,
        .choice_payload_access => .choice_payload,
        .error_propagation => .error_propagation,
        .error_context => .error_context,
        .index_access => .index,
        .index_assignment => .index_store,
        .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo => .binary,
        .compare_equal, .compare_not_equal, .compare_less, .compare_greater, .compare_less_equal, .compare_greater_equal => .comparison,
        .logical_and, .logical_or => .logical,
        .if_statement => .if_statement,
        .while_statement => .while_statement,
        .for_value, .for_borrow, .for_mut_borrow, .for_move => .for_each,
        .match_statement, .match_case_value, .match_case_borrow, .match_case_mut_borrow, .match_case_move => .match,
        .defer_statement => .defer_value,
        .address_of, .address_of_mut => .address_of,
        .dereference => .dereference,
        .pointer_assignment => .pointer_store,
        .move_expression => .move_value,
        .struct_value_literal => .struct_value,
        .list_literal => .list_value,
        .return_statement => .return_statement,
        else => .other,
    };
}

test "module parameterized lowerer stores dependent shapes without syntax references" {
    try std.testing.expect(@sizeOf(ir.ParameterizedTypeId) == 4);
    try std.testing.expect(@sizeOf(ir.ParameterizedNodeId) == 4);
}
