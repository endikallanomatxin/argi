const std = @import("std");
const graph_mod = @import("graph.zig");
const module_mod = @import("../module/graph.zig");
const storage_mod = @import("../module/parameterized/storage.zig");
const core_mod = @import("core.zig");
const generic_mod = @import("generics.zig");
const functions_mod = @import("generic_functions.zig");
const abstracts_mod = @import("abstracts.zig");
const reach_context = @import("reach_context.zig");
const types = @import("types.zig");

pub const Participant = union(enum) {
    known: graph_mod.GlobalTypeId,
    family: graph_mod.GlobalDeclId,
    inferred,
};

pub const Selection = struct {
    /// Owned by the caller; the final participant is the completed Args record.
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

/// Infer participants from an argument-record pattern and lexical capabilities.
/// Associated results never contribute bindings or select an implementation.
pub const Resolver = struct {
    graph: *graph_mod.GlobalSemanticGraph,
    modules: []const module_mod.ModuleSemanticGraph,
    core: *core_mod.Resolver,
    generics: *generic_mod.Resolver,
    functions: *functions_mod.Resolver,
    abstracts: *abstracts_mod.Resolver,

    pub fn infer(self: *Resolver, declaration: graph_mod.GlobalDeclId, prefix: []const Participant, input: graph_mod.GlobalNodeId, reach: reach_context.Context) !Result {
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
                if (template.participants.len != prefix.len + 1) continue;
                if (try self.abstracts.resolveDeclarationRef(module_index, template.contract_ref, .abstract_type) != declaration) continue;
                const patterns = storage.ir.generic_arguments.items[template.participants.start..][0..template.participants.len];
                for (patterns) |pattern| if (pattern.value != .type) continue :templates;
                var bindings = try generic_mod.Resolver.Bindings.init(allocator, storage.comptime_parameters.items.len);
                defer bindings.deinit(allocator);
                for (prefix, 0..) |participant, index| switch (participant) {
                    .known => |known| if (!try self.abstracts.inferConstraintTypePattern(module_index, patterns[index].value.type, known, &bindings)) {
                        continue :templates;
                    },
                    .family => |family| {
                        const pattern = storage.ir.types.items[@intFromEnum(patterns[index].value.type)];
                        if (pattern == .resolved and pattern.resolved == .generic) {
                            if (try self.generics.resolveParameterizedDeclaration(module_index, pattern.resolved.generic.base) != family) continue :templates;
                        } else if (pattern == .concrete) {
                            const closed = try self.generics.instantiateParameterizedType(module_index, patterns[index].value.type, &bindings);
                            const identity = switch (self.graph.resolvedSemanticType(closed) orelse continue :templates) {
                                .declared => |id| id,
                                .generic => |generic| generic.base,
                                else => continue :templates,
                            };
                            if (identity != family) continue :templates;
                        } else continue :templates;
                    },
                    .inferred => {},
                };
                has_prefix = true;
                const args_pattern = patterns[prefix.len].value.type;
                if (storage.ir.types.items[@intFromEnum(args_pattern)] != .concrete and
                    !try self.functions.inferArgumentRecordBindings(module_index, args_pattern, input, reach, &bindings)) continue;
                if (!try self.abstracts.validateParameterizedImplementationConstraints(module_index, template.parameters, &bindings)) continue;
                const participants = try allocator.alloc(graph_mod.GlobalTypeId, patterns.len);
                var retained = false;
                defer if (!retained) allocator.free(participants);
                for (patterns, 0..) |pattern, index| {
                    participants[index] = self.generics.instantiateParameterizedType(module_index, pattern.value.type, &bindings) catch |err| switch (err) {
                        error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => continue :templates,
                        else => return err,
                    };
                }
                const fields = types.fields(self.graph, participants[prefix.len]) orelse continue;
                switch (try self.core.matchCallInputWithReach(fields, input, reach)) {
                    .score => {},
                    .deferred => {
                        deferred = true;
                        continue;
                    },
                    .no_match => {
                        if (self.core.matchCallInput(fields, input) == .score) {
                            for (self.graph.fields.items[fields.start..][0..fields.len], 0..) |field, position| {
                                if (self.core.callArgumentNamed(supplied, position, self.graph.text(field.name)) != null) continue;
                                const fallback = field.default_value orelse continue;
                                if (self.graph.node(fallback).content != .reach_directive) continue;
                                if (try self.core.probeReachedDefaultWithCompatibility(reach, field, fallback, null) == .unavailable) {
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
                if (candidate.template.parameters.len != 0 and other.template.parameters.len == 0 and sameParticipants(self.graph, candidate.participants, other.participants)) {
                    dominated = true;
                    break;
                }
                if (try self.abstracts.patternTupleCovers(candidate.module, candidate.template, other.module, other.template) and
                    !try self.abstracts.patternTupleCovers(other.module, other.template, candidate.module, candidate.template))
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
