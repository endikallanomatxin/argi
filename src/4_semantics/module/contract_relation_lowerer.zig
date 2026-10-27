const type_arguments = @import("type_arguments.zig");
const parameterized_lowerer = @import("parameterized/lowerer.zig");
const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const parameterized_storage = @import("parameterized/storage.zig");
const ir = @import("parameterized/ir.zig");
const writer_mod = @import("writer.zig");
const type_lowerer = @import("type_lowerer.zig");
const initializer_lowerer = @import("initializer_lowerer.zig");
const primitives = @import("../primitives/schema.zig");

pub const Stats = struct {
    implementations: u32 = 0,
};

const Param = parameterized_lowerer.ParameterBinding;

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
    diagnostics: ?*@import("../../1_base/diagnostic.zig").Diagnostics,
) !Stats {
    var ctx = Context{
        .allocator = allocator,
        .graph = graph,
        .files = files,
        .writer = writer_mod.Writer.init(allocator, graph),
        .params = std.array_list.Managed(Param).init(allocator),
        .diagnostics = diagnostics,
    };
    defer ctx.params.deinit();
    return ctx.run();
}

const Context = struct {
    diagnostics: ?*@import("../../1_base/diagnostic.zig").Diagnostics = null,
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    writer: writer_mod.Writer,
    params: std.array_list.Managed(Param),
    file_index: u32 = 0,
    tree: *const syn.FileSyntaxTree = undefined,
    source: []const u8 = &.{},

    fn run(self: *Context) !Stats {
        var stats: Stats = .{};
        for (self.files, 0..) |file, raw_file| {
            self.file_index = @intCast(raw_file);
            self.tree = file.tree;
            self.source = file.source;
            for (self.tree.roots) |node| switch (self.tree.tag(node)) {
                .contract_conformance => {
                    try self.lowerConformance(node, self.tree.contractConformance(node).?);
                    stats.implementations += 1;
                },
                else => {},
            };
        }
        return stats;
    }

    fn conformanceError(self: *Context, node: syn.NodeIndex, message: []const u8) !void {
        if (self.diagnostics) |bag| {
            try bag.add(self.tree.location(node), .semantic, "{s}", .{message});
            return error.Reported;
        }
        return error.InvalidContractConformance;
    }

    fn lowerConformance(self: *Context, node: syn.NodeIndex, relation: syn.ContractConformance) !void {
        self.params.clearRetainingCapacity();
        const parameters = try self.lowerParams(relation.generic_params, relation.generic_params_struct);
        const syntax_type = self.tree.syntaxType(relation.contract_type) orelse return error.ExpectedContractType;
        const base_node = if (syntax_type == .generic) syntax_type.generic.base else relation.contract_type;
        const base = self.tree.syntaxType(base_node) orelse return error.ExpectedContractType;
        if (base != .name) try self.conformanceError(node, "implement requires a named contract");
        const name = self.tree.tokenTextFromSource(self.source, base.name.name_token);
        const reference = try self.declarationRef(base_node, name, .contract);
        const participants = try self.lowerConformanceArguments(if (syntax_type == .generic) syntax_type.generic.arguments else null);
        var operations: primitives.Range(parameterized_storage.ContractOperationId) = .{ .start = 0, .len = 0 };
        const associated = blk: {
            var arguments: std.ArrayList(ir.GenericArgument) = .empty;
            defer arguments.deinit(self.allocator);
            const operation_start: u32 = @intCast(self.graph.semantic.parameterized_storage.contract_operations.items.len);
            for (self.tree.structTypeLiteral(relation.implementation_members).?.fields) |member_node| {
                const member = self.tree.structTypeField(member_node).?;
                const member_name = self.tree.tokenTextFromSource(self.source, member.name_token);
                const value = member.default_value orelse return error.InvalidContractArgument;
                if (member.type_node) |annotation| {
                    if (self.tree.parameterizedDefinition(annotation) != null) {
                        var lowerer = self.parameterizedContext();
                        defer lowerer.bindings.deinit();
                        const argument = lowerer.lowerFamilyValue(value) catch |err| switch (err) {
                            error.ExpectedParameterizedDefinition => {
                                try self.conformanceError(member_node, "associated family implementations require a parameterized definition value");
                                unreachable;
                            },
                            else => return err,
                        };
                        try arguments.append(self.allocator, .{ .name = try self.writer.addString(member_name), .value = argument });
                        continue;
                    }
                    const kind = self.tree.syntaxType(annotation) orelse return error.InvalidContractArgument;
                    if (kind != .name) try self.conformanceError(member_node, "associated implementation elements require Type or Int annotations");
                    const kind_name = self.tree.tokenTextFromSource(self.source, kind.name.name_token);
                    const argument: ir.GenericArgument.Value = if (std.mem.eql(u8, kind_name, "Type"))
                        .{ .type = try self.lowerConformanceType(value) }
                    else if (std.mem.eql(u8, kind_name, "Int"))
                        .{ .comptime_int = try self.lowerConformanceInt(value) }
                    else {
                        try self.conformanceError(member_node, "associated implementation elements require Type or Int annotations");
                        unreachable;
                    };
                    try arguments.append(self.allocator, .{ .name = try self.writer.addString(member_name), .value = argument });
                    continue;
                }
                const storage = &self.graph.semantic.parameterized_storage;
                for (storage.contract_operations.items[operation_start..]) |previous| {
                    if (std.mem.eql(u8, self.graph.text(previous.name), member_name))
                        try self.conformanceError(member_node, "duplicate implementation operation");
                }
                if (self.tree.functionDeclaration(value) != null) {
                    const declaration = for (self.graph.declarations.items, 0..) |candidate, raw| {
                        if (candidate.kind == .function and candidate.module_file_index == self.file_index and candidate.source_offset == self.tree.location(value).offset)
                            break @as(entities.ModuleDeclId, @enumFromInt(@as(u32, @intCast(raw))));
                    } else return error.MissingImplementationFunction;
                    try storage.contract_operations.append(self.allocator, .{
                        .instantiate_associated = true,
                        .name = try self.writer.addString(member_name),
                        .function = .{ .module = declaration },
                        .source = .{ .file_index = self.sourceRef(member_node).file_index, .offset = self.tree.tokenLocation(member.name_token).offset },
                    });
                    continue;
                }
                var qualifier: ?syn.TokenIndex = null;
                const function_token = switch (self.tree.tag(value)) {
                    .identifier => self.tree.mainToken(value),
                    .struct_field_access => field: {
                        const access = self.tree.structFieldAccess(value).?;
                        var root = access.value;
                        while (self.tree.structFieldAccess(root)) |parent| root = parent.value;
                        if (self.tree.tag(root) != .identifier) {
                            try self.conformanceError(member_node, "implementation operation aliases require an ordinary function name");
                            unreachable;
                        }
                        qualifier = self.tree.mainToken(root);
                        break :field access.field_token;
                    },
                    else => {
                        try self.conformanceError(member_node, "implementation operation aliases require an ordinary function name");
                        unreachable;
                    },
                };
                const function_ref = try self.writer.addExternalRef(.{
                    .kind = .function,
                    .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, function_token)),
                    .module_path = if (qualifier) |token| try @import("qualified_path.zig").intern(&self.writer, self.tree, self.source, token, function_token) else null,
                    .source = .{ .file_index = self.sourceRef(member_node).file_index, .offset = self.tree.tokenLocation(function_token).offset },
                });
                try storage.contract_operations.append(self.allocator, .{
                    .name = try self.writer.addString(member_name),
                    .function = .{ .external = function_ref },
                    .source = .{ .file_index = self.sourceRef(member_node).file_index, .offset = self.tree.tokenLocation(member.name_token).offset },
                });
            }
            operations = .{ .start = operation_start, .len = @intCast(self.graph.semantic.parameterized_storage.contract_operations.items.len - operation_start) };
            break :blk try self.publishConformanceArguments(arguments.items);
        };
        try self.graph.semantic.parameterized_storage.contract_conformances.ensureUnusedCapacity(self.allocator, 1);
        const domains = try self.lowerDomainMappings(relation.domain_mapping);
        self.graph.semantic.parameterized_storage.contract_conformances.appendAssumeCapacity(.{
            .parameters = parameters,
            .operations = operations,
            .contract_ref = reference,
            .participants = participants,
            .associated_arguments = associated,
            .source = self.sourceRef(node),
            .domains = domains,
        });
    }

    fn lowerConformanceArguments(self: *Context, optional: ?syn.NodeIndex) !primitives.Range(ir.ParameterizedGenericArgId) {
        var arguments: std.ArrayList(ir.GenericArgument) = .empty;
        defer arguments.deinit(self.allocator);
        if (optional) |node| {
            for (self.tree.specializationArguments(node).?.fields) |field_node| {
                const field = self.tree.structTypeField(field_node).?;
                const value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                    .{ .type = try self.lowerConformanceType(type_node) }
                else if (field.default_value) |value_node|
                    .{ .comptime_int = try self.lowerConformanceInt(value_node) }
                else
                    return error.InvalidContractArgument;
                try arguments.append(self.allocator, .{
                    .name = try self.writer.addString(type_arguments.name(self.tree, self.source, field, "")),
                    .value = value,
                });
            }
        }
        return self.publishConformanceArguments(arguments.items);
    }

    fn publishConformanceArguments(self: *Context, arguments: []const ir.GenericArgument) !primitives.Range(ir.ParameterizedGenericArgId) {
        const pool = &self.graph.semantic.parameterized_storage.ir.generic_arguments;
        const start: u32 = @intCast(pool.items.len);
        try pool.appendSlice(self.allocator, arguments);
        return .{ .start = start, .len = @intCast(arguments.len) };
    }

    fn lowerConformanceType(self: *Context, node: syn.NodeIndex) !ir.ParameterizedTypeId {
        // Closed definitions retain unresolved module projections until all
        // conformance evidence is published. Generic patterns use the same IR
        // pool, with parameter leaves instead of concrete module type leaves.
        if (self.params.items.len != 0) return self.lowerParameterizedType(node);
        const pool = &self.graph.semantic.parameterized_storage.ir.types;
        const ty = try self.lowerModuleType(node);
        const index: u32 = @intCast(pool.items.len);
        try pool.append(self.allocator, .{ .concrete = ty });
        return @enumFromInt(index);
    }

    fn lowerConformanceInt(self: *Context, node: syn.NodeIndex) !ir.ParameterizedIntExprId {
        var lowerer = self.parameterizedContext();
        defer lowerer.bindings.deinit();
        return lowerer.lowerIntExpression(node);
    }

    fn lowerDomainMappings(self: *Context, optional: ?syn.NodeIndex) ![]const parameterized_storage.DomainMapping {
        const node = optional orelse return &.{};
        var result: std.ArrayList(parameterized_storage.DomainMapping) = .empty;
        defer result.deinit(self.allocator);
        errdefer for (result.items) |domain| domain.deinit(self.allocator);
        for (self.tree.codeBlock(node).?.statements) |statement| {
            const clause = if (self.tree.tag(statement) == .expression_statement) self.tree.data(statement).node else statement;
            const call = self.tree.functionCall(clause) orelse return error.InvalidStorageDomainMapping;
            if (call.module_qualifier != null or call.specialization_arguments != null) return error.InvalidStorageDomainMapping;
            var paths: std.ArrayList(parameterized_storage.DomainMapping.Path) = .empty;
            defer paths.deinit(self.allocator);
            errdefer for (paths.items) |path| self.allocator.free(path.fields);
            for (self.tree.structValueLiteral(call.input).?.fields) |argument| {
                const field = self.tree.valueField(argument).?;
                if (field.name_token != null) return error.InvalidStorageDomainMapping;
                var names: std.ArrayList(primitives.StringRange) = .empty;
                defer names.deinit(self.allocator);
                try self.lowerDomainPath(field.value, &names);
                if (names.items.len == 0) return error.InvalidStorageDomainMapping;
                try paths.ensureUnusedCapacity(self.allocator, 1);
                paths.appendAssumeCapacity(.{ .fields = try names.toOwnedSlice(self.allocator) });
            }
            if (paths.items.len == 0) return error.InvalidStorageDomainMapping;
            try result.ensureUnusedCapacity(self.allocator, 1);
            const name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, call.callee_token));
            result.appendAssumeCapacity(.{
                .name = name,
                .paths = try paths.toOwnedSlice(self.allocator),
            });
        }
        return result.toOwnedSlice(self.allocator);
    }

    fn lowerDomainPath(self: *Context, node: syn.NodeIndex, names: *std.ArrayList(primitives.StringRange)) anyerror!void {
        if (self.tree.structFieldAccess(node)) |field| {
            try self.lowerDomainPath(field.value, names);
            try names.append(self.allocator, try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.field_token)));
            return;
        }
        if (self.tree.tag(node) != .identifier or !std.mem.eql(u8, self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node)), "self")) return error.InvalidStorageDomainMapping;
    }

    fn lowerParams(self: *Context, params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) !primitives.Range(ir.ComptimeParameterId) {
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len);
        if (params_struct) |node| {
            const literal = self.tree.parameterList(node) orelse return error.InvalidGenericParameters;

            // Register every relation parameter before lowering its metadata.
            // Bounds may reference associated parameters declared later.
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
                const name_text = self.tree.tokenTextFromSource(self.source, field.name_token);
                _ = field.type_node orelse return error.InvalidGenericParameter;
                const kind: parameterized_storage.ComptimeParameterKind =
                    if (self.tree.parameterizedDefinition(field.type_node.?) != null) .definition else if (parameterized_lowerer.isTypeParameter(self.tree, self.source, field)) .type else .comptime_int;
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = kind,
                });
                try self.params.append(.{ .name = name_text, .id = id, .kind = kind });
            }

            for (literal.fields, 0..) |field_node, offset| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
                const value_type_node = field.type_node orelse return error.InvalidGenericParameter;
                const parameter_record = &self.graph.semantic.parameterized_storage.comptime_parameters.items[
                    start + @as(u32, @intCast(offset))
                ];
                var lowerer = self.parameterizedContext();
                defer lowerer.bindings.deinit();
                switch (parameter_record.kind) {
                    .definition => {
                        const signature = try lowerer.lowerDefinitionParameterSignature(value_type_node);
                        self.graph.semantic.parameterized_storage.comptime_parameters.items[start + @as(u32, @intCast(offset))].family_parameters = signature;
                    },
                    .comptime_int => parameter_record.value_type = try lowerer.lowerType(value_type_node, false),
                    .type => {
                        if (!isTypeName(self.tree, self.source, value_type_node, "Type"))
                            parameter_record.constraint = try lowerer.lowerContractConstraint(value_type_node);
                    },
                }
            }
        } else {
            for (params) |param| {
                const name_text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(param));
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = .type,
                });
                try self.params.append(.{ .name = name_text, .id = id, .kind = .type });
            }
        }
        return .{ .start = start, .len = @intCast(if (params_struct) |node| self.tree.parameterList(node).?.fields.len else params.len) };
    }

    fn lowerParameterizedType(self: *Context, node: syn.NodeIndex) !ir.ParameterizedTypeId {
        var lowerer = self.parameterizedContext();
        defer lowerer.bindings.deinit();
        return lowerer.lowerType(node, false);
    }

    fn parameterizedContext(self: *Context) parameterized_lowerer.Context {
        return .{
            .allocator = self.allocator,
            .graph = self.graph,
            .files = self.files,
            .writer = self.writer,
            .parameters = self.params,
            .bindings = .init(self.allocator),
            .file_index = self.file_index,
            .tree = self.tree,
            .source = self.source,
        };
    }

    fn lowerModuleType(self: *Context, node: syn.NodeIndex) !entities.ModuleTypeId {
        var lowerer = type_lowerer.Context{
            .graph = self.graph,
            .writer = &self.writer,
            .file_index = self.file_index,
            .tree = self.tree,
            .source = self.source,
        };
        const ty = try lowerer.lower(node);
        try initializer_lowerer.lowerAnonymousFieldDefaults(self.allocator, self.graph, self.files, self.file_index, node, ty, self.diagnostics);
        return ty;
    }

    fn declarationRef(self: *Context, node: syn.NodeIndex, name: []const u8, kind: entities.ExternalKind) !ir.DeclarationRef {
        const syntax_type = self.tree.syntaxType(node);
        const qualifier = if (syntax_type) |ty| (if (ty == .name) ty.name.qualifier_token else null) else null;
        if (qualifier == null) for (self.graph.declarationsNamed(name)) |decl| {
            const candidate = self.graph.declarations.items[@intFromEnum(decl)];
            if ((kind == .contract and candidate.kind == .contract_type) or (kind == .type and candidate.kind == .type))
                return .{ .module = decl };
        };
        const external = try self.writer.addExternalRef(.{
            .kind = kind,
            .module_path = if (qualifier) |token| try @import("qualified_path.zig").intern(&self.writer, self.tree, self.source, token, syntax_type.?.name.name_token) else null,
            .name = try self.writer.addString(name),
            .source = self.sourceRef(node),
        });
        return .{ .external = external };
    }

    fn sourceRef(self: *Context, node: syn.NodeIndex) primitives.SourceRef {
        return .{ .file_index = self.file_index, .offset = self.tree.location(node).offset };
    }
};

fn isTypeName(tree: *const syn.FileSyntaxTree, source: []const u8, node: syn.NodeIndex, expected: []const u8) bool {
    const ty = tree.syntaxType(node) orelse return false;
    return ty == .name and ty.name.qualifier_token == null and std.mem.eql(u8, tree.tokenTextFromSource(source, ty.name.name_token), expected);
}
