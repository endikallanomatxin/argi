const std = @import("std");
const graph_mod = @import("graph.zig");
const module_mod = @import("../module/graph.zig");
const storage_mod = @import("../module/parameterized/storage.zig");
const core_mod = @import("core.zig");
const generic_mod = @import("generics.zig");
const functions_mod = @import("generic_functions.zig");
const contracts_mod = @import("contracts.zig");
const reach_context = @import("reach_context.zig");
const types = @import("types.zig");
const primitives = @import("../primitives/schema.zig");
const ir = @import("../module/parameterized/ir.zig");

pub const Participant = union(enum) {
    known: graph_mod.GlobalTypeId,
    family: graph_mod.GlobalFamilyDefinitionId,
    partial: struct { family: graph_mod.GlobalFamilyDefinitionId, arguments: primitives.Range(graph_mod.GlobalGenericArgId) },
    inferred,
};

pub const Selection = struct {
    /// Owned by the caller; contains only the contract participants.
    participants: []const graph_mod.GlobalTypeId,
};

pub const Result = union(enum) {
    selected: Selection,
    none,
    deferred,
    ambiguous,
    missing_reach: graph_mod.Field,
    incompatible_arguments,
};

/// Infer participants from operation signatures and lexical capabilities.
/// Associated results never contribute bindings or select an implementation.
pub const Resolver = struct {
    graph: *graph_mod.GlobalSemanticGraph,
    modules: []const module_mod.ModuleSemanticGraph,
    core: *core_mod.Resolver,
    generics: *generic_mod.Resolver,
    functions: *functions_mod.Resolver,
    contracts: *contracts_mod.Resolver,

    fn bindPartialTargetExplicit(self: *Resolver, module_index: usize, pattern_id: ir.ParameterizedTypeId, family: graph_mod.GlobalFamilyDefinitionId, arguments: primitives.Range(graph_mod.GlobalGenericArgId), bindings: *generic_mod.Resolver.Bindings) !bool {
        const located = self.generics.findTypeParameterized(family) orelse return false;
        const family_module = &self.modules[located.module_index];
        const parameters = located.parameterized.parameters;
        var supplied = try generic_mod.Resolver.Bindings.init(self.core.allocator, family_module.semantic.parameterized_storage.comptime_parameters.items.len);
        defer supplied.deinit(self.core.allocator);
        // The constructor validates names, duplicates and kinds before probing
        // candidates. Do not disguise malformed arguments as a losing pattern.
        try self.generics.bindGlobalArgumentsPartial(located.module_index, parameters, arguments, &supplied);
        const pattern = self.modules[module_index].semantic.parameterized_storage.ir.types.items[@intFromEnum(pattern_id)];
        if (pattern == .resolved and pattern.resolved == .generic) {
            const generic = pattern.resolved.generic;
            if (try self.generics.resolveParameterizedFamily(module_index, generic.base) != family) return false;
            return self.matchPartialBindings(module_index, generic.arguments, located, &supplied, bindings);
        }
        const closed = self.generics.instantiateParameterizedType(module_index, pattern_id, bindings) catch |err| switch (err) {
            error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => return false,
            else => return err,
        };
        const identity = switch (self.graph.resolvedSemanticType(closed) orelse return false) {
            .generic => |value| value,
            else => return false,
        };
        if (identity.base != family) return false;
        for (0..parameters.len) |index| {
            const raw = parameters.start + index;
            const parameter = family_module.semantic.parameterized_storage.comptime_parameters.items[raw];
            const actual = self.generics.findGlobalArgument(family_module.text(parameter.name), identity.arguments, index) orelse return false;
            if (supplied.types[raw]) |ty| {
                if (actual.value != .type or !types.equal(self.graph, ty, actual.value.type)) return false;
            }
            if (supplied.definitions[raw]) |definition| {
                if (actual.value != .definition or definition.origin != actual.value.definition.origin or
                    !types.genericArgumentsEqual(self.graph, definition.captures, actual.value.definition.captures)) return false;
            }
            if (supplied.ints[raw]) |integer| {
                if (actual.value != .comptime_int or integer != actual.value.comptime_int) return false;
            }
        }
        return true;
    }

    fn completePartialTargetDefaults(self: *Resolver, module_index: usize, pattern_id: ir.ParameterizedTypeId, family: graph_mod.GlobalFamilyDefinitionId, bindings: *generic_mod.Resolver.Bindings) !bool {
        const pattern = self.modules[module_index].semantic.parameterized_storage.ir.types.items[@intFromEnum(pattern_id)];
        if (pattern != .resolved or pattern.resolved != .generic) return true;
        const generic = pattern.resolved.generic;
        const located = self.generics.findTypeParameterized(family) orelse return false;
        const family_module = &self.modules[located.module_index];
        const parameters = located.parameterized.parameters;
        var inferred = try generic_mod.Resolver.Bindings.init(self.core.allocator, family_module.semantic.parameterized_storage.comptime_parameters.items.len);
        defer inferred.deinit(self.core.allocator);
        // Recover the current bindings after input inference; explicit arguments
        // have already constrained the pattern and are not parsed a second time.
        for (0..parameters.len) |index| {
            const raw = parameters.start + index;
            const parameter = family_module.semantic.parameterized_storage.comptime_parameters.items[raw];
            const argument = self.generics.findPatternArgument(module_index, generic.arguments, index, family_module.text(parameter.name)) orelse continue;
            switch (argument.value) {
                .projection => |projection| {
                    const value = self.generics.instantiateArgumentProjection(module_index, projection, bindings) catch |err| switch (err) {
                        error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => continue,
                        else => return err,
                    };
                    switch (value) {
                        .definition => |v| inferred.definitions[raw] = v,
                        .type => |v| inferred.types[raw] = v,
                        .comptime_int => |v| inferred.ints[raw] = v,
                    }
                },
                .type => |ty| inferred.types[raw] = self.generics.instantiateParameterizedType(module_index, ty, bindings) catch |err| switch (err) {
                    error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => null,
                    else => return err,
                },
                .definition => |definition| inferred.definitions[raw] = self.generics.instantiateDefinitionValue(module_index, definition, bindings) catch |err| switch (err) {
                    error.UnboundDefinitionParameter => null,
                    else => return err,
                },
                .comptime_int => |expression| inferred.ints[raw] = self.generics.evalInt(module_index, expression, bindings) catch |err| switch (err) {
                    error.UnboundComptimeParameter => null,
                    else => return err,
                },
            }
        }
        self.generics.applyParameterDefaults(located.module_index, parameters, &inferred) catch |err| switch (err) {
            error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => return false,
            else => return err,
        };
        return self.matchPartialBindings(module_index, generic.arguments, located, &inferred, bindings);
    }

    fn matchPartialBindings(self: *Resolver, module_index: usize, patterns: primitives.Range(ir.ParameterizedGenericArgId), located: generic_mod.Resolver.LocatedTypeParameterized, actual: *const generic_mod.Resolver.Bindings, bindings: *generic_mod.Resolver.Bindings) !bool {
        const module = &self.modules[located.module_index];
        const parameters = located.parameterized.parameters;
        for (0..parameters.len) |index| {
            const raw = parameters.start + index;
            const parameter = module.semantic.parameterized_storage.comptime_parameters.items[raw];
            const argument = self.generics.findPatternArgument(module_index, patterns, index, module.text(parameter.name)) orelse continue;
            switch (argument.value) {
                .projection => |projection| {
                    const value = try self.generics.instantiateArgumentProjection(module_index, projection, bindings);
                    const bound_value: graph_mod.GenericArgument.Value = switch (parameter.kind) {
                        .definition => .{ .definition = actual.definitions[raw] orelse return false },
                        .type => .{ .type = actual.types[raw] orelse return false },
                        .comptime_int => .{ .comptime_int = actual.ints[raw] orelse return false },
                    };
                    if (!types.genericArgumentValuesEqual(self.graph, value, bound_value)) return false;
                },
                .type => |ty| if (actual.types[raw]) |value| {
                    if (!try self.contracts.inferConstraintTypePattern(module_index, ty, value, bindings)) return false;
                },
                .definition => |definition| if (actual.definitions[raw]) |value| {
                    if (!try self.generics.inferDefinitionValue(module_index, definition, value, bindings)) return false;
                },
                .comptime_int => |expression| if (actual.ints[raw]) |value| {
                    if (!try self.contracts.inferConstraintIntPattern(module_index, expression, value, bindings)) return false;
                },
            }
        }
        return true;
    }

    /// Infer unknown participants from operation inputs and lexical capabilities.
    /// Associated results never select an implementation.
    pub fn inferOperation(self: *Resolver, declaration: graph_mod.GlobalFamilyDefinitionId, prefix: []const Participant, operation_name: []const u8, input: graph_mod.GlobalNodeId, reach: reach_context.Context) !Result {
        return self.inferOperationWithArguments(declaration, prefix, operation_name, input, reach, .{ .start = 0, .len = 0 });
    }

    pub fn inferOperationWithArguments(self: *Resolver, declaration: graph_mod.GlobalFamilyDefinitionId, prefix: []const Participant, operation_name: []const u8, input: graph_mod.GlobalNodeId, reach: reach_context.Context, arguments: primitives.Range(graph_mod.GlobalGenericArgId)) !Result {
        const allocator = self.core.allocator;
        const Candidate = struct { module: usize, template: storage_mod.ContractConformance, participants: []const graph_mod.GlobalTypeId };
        var candidates: std.ArrayList(Candidate) = .empty;
        defer {
            for (candidates.items) |candidate| allocator.free(candidate.participants);
            candidates.deinit(allocator);
        }
        var has_prefix = false;
        var deferred = false;
        var missing_reach: ?graph_mod.Field = null;
        for (0..reach.bindingCount()) |index| {
            if (self.graph.isBindingTypeUnresolved(reach.bindingAt(index))) deferred = true;
        }
        const supplied = self.graph.node(input).content.struct_value_literal;
        for ([_]@TypeOf(supplied.fields){ supplied.fields, supplied.assumed_fields }) |fields| {
            for (self.graph.value_fields.items[fields.start..][0..fields.len]) |field| {
                if (self.graph.node(field.value).ty) |ty| {
                    if (self.graph.isTypeUnresolved(ty)) deferred = true;
                } else deferred = true;
            }
        }
        for (self.modules, 0..) |*module, module_index| {
            const storage = &module.semantic.parameterized_storage;
            templates: for (storage.contract_conformances.items) |template| {
                if (template.participants.len != prefix.len) continue;
                if (try self.contracts.resolveDeclarationRef(module_index, template.contract_ref, .contract_type) != declaration) continue;
                const patterns = storage.ir.generic_arguments.items[template.participants.start..][0..template.participants.len];
                for (patterns) |pattern| if (pattern.value != .type) continue :templates;
                var bindings = try generic_mod.Resolver.Bindings.init(allocator, storage.comptime_parameters.items.len);
                defer bindings.deinit(allocator);
                for (prefix, 0..) |participant, index| switch (participant) {
                    .known => |known| if (!try self.contracts.inferConstraintTypePattern(module_index, patterns[index].value.type, known, &bindings)) {
                        continue :templates;
                    },
                    .family => |family| {
                        const pattern = storage.ir.types.items[@intFromEnum(patterns[index].value.type)];
                        if (pattern == .resolved and pattern.resolved == .generic) {
                            if (try self.generics.resolveParameterizedFamily(module_index, pattern.resolved.generic.base) != family) continue :templates;
                        } else if (pattern == .concrete) {
                            const closed = try self.generics.instantiateParameterizedType(module_index, patterns[index].value.type, &bindings);
                            const identity = switch (self.graph.resolvedSemanticType(closed) orelse continue :templates) {
                                .definition => |id| id,
                                .generic => |generic| generic.base,
                                else => continue :templates,
                            };
                            if (identity != family) continue :templates;
                        } else continue :templates;
                    },
                    .partial => |partial| if (!try self.bindPartialTargetExplicit(module_index, patterns[index].value.type, partial.family, partial.arguments, &bindings)) continue :templates,
                    .inferred => {},
                };
                has_prefix = true;
                const operation_input: graph_mod.GlobalTypeId = blk: {
                    const operation = for (storage.contract_operations.items[template.operations.start..][0..template.operations.len]) |candidate| {
                        if (std.mem.eql(u8, module.text(candidate.name), operation_name)) break candidate;
                    } else continue :templates;
                    break :blk self.functions.inferImplementationInput(module_index, operation, template.parameters, input, reach, &bindings, arguments, template.associated_arguments) catch |err| switch (err) {
                        error.ConflictingGenericArgument => null,
                        else => return err,
                    } orelse continue :templates;
                };
                for (prefix, 0..) |participant, index| {
                    if (participant == .partial) {
                        const partial = participant.partial;
                        if (!try self.completePartialTargetDefaults(module_index, patterns[index].value.type, partial.family, &bindings)) continue :templates;
                    }
                }
                if (!try self.contracts.validateParameterizedImplementationConstraints(module_index, template.parameters, &bindings)) continue;
                const participants = try allocator.alloc(graph_mod.GlobalTypeId, patterns.len);
                var retained = false;
                defer if (!retained) allocator.free(participants);
                for (patterns, 0..) |pattern, index| {
                    participants[index] = self.generics.instantiateParameterizedType(module_index, pattern.value.type, &bindings) catch |err| switch (err) {
                        error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => continue :templates,
                        else => return err,
                    };
                }
                const fields = types.fields(self.graph, operation_input) orelse continue;
                switch (try self.core.matchCallInputWithReach(fields, input, reach)) {
                    .applicable => {},
                    .deferred => {
                        deferred = true;
                        continue;
                    },
                    .no_match => {
                        if (self.core.matchCallInput(fields, input) == .applicable) {
                            for (self.graph.fields.items[fields.start..][0..fields.len], 0..) |field, position| {
                                if (self.core.callArgumentNamed(supplied, position, self.graph.text(field.name)) != null) continue;
                                const fallback = field.default_value orelse continue;
                                if (self.graph.node(fallback).content != .reach_directive) continue;
                                if (try self.core.probeReachedDefault(reach, field, fallback) == .unavailable) {
                                    missing_reach = field;
                                    break;
                                }
                            }
                        }
                        continue;
                    },
                }
                try candidates.append(allocator, .{ .module = module_index, .template = template, .participants = participants });
                retained = true;
            }
        }
        var selected: ?usize = null;
        for (candidates.items, 0..) |candidate, index| {
            var dominated = false;
            for (candidates.items, 0..) |other, other_index| {
                if (index == other_index) continue;
                // Specificity selects a conformance for one concrete tuple;
                // it cannot choose between different inferred destinations.
                if (!sameParticipants(self.graph, candidate.participants, other.participants)) continue;
                if (candidate.template.parameters.len != 0 and other.template.parameters.len == 0 and sameParticipants(self.graph, candidate.participants, other.participants)) {
                    dominated = true;
                    break;
                }
                if (try self.contracts.patternTupleCovers(candidate.module, candidate.template, other.module, other.template) and
                    !try self.contracts.patternTupleCovers(other.module, other.template, candidate.module, candidate.template))
                {
                    dominated = true;
                    break;
                }
            }
            if (dominated) continue;
            if (selected != null) return .ambiguous;
            selected = index;
        }
        if (selected) |index| return .{ .selected = .{ .participants = try allocator.dupe(graph_mod.GlobalTypeId, candidates.items[index].participants) } };
        if (!has_prefix) return .none;
        if (deferred) return .deferred;
        if (missing_reach) |field| return .{ .missing_reach = field };
        return .incompatible_arguments;
    }
};

fn sameParticipants(graph: *const graph_mod.GlobalSemanticGraph, left: []const graph_mod.GlobalTypeId, right: []const graph_mod.GlobalTypeId) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!types.equal(graph, a, b)) return false;
    return true;
}
