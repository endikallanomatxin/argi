//! Graph-aware receipt paths in execution-transfer contracts and summaries.
const std = @import("std");
const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const contracts = @import("contracts.zig");
const facts = @import("safety_facts.zig");
const Projection = @import("place.zig").Projection;

fn selectedType(graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.Function, path: facts.InputPath, follow_input: bool) ?graph_mod.GlobalTypeId {
    if (path.storage_domain != null or path.input_index >= function.input.len) return null;
    var ty = graph.fields.items[function.input.start + path.input_index].ty;
    if (follow_input and path.projections.len == 0) {
        const semantic = graph.resolvedSemanticType(ty) orelse return null;
        if (semantic == .pointer) ty = semantic.pointer.child;
    }
    for (path.projections) |projection| {
        if (follow_input and projection != .dereference) {
            var depth: usize = 0;
            while (true) {
                const semantic = graph.resolvedSemanticType(ty) orelse return null;
                if (semantic != .pointer) break;
                if (depth == 128) return null;
                depth += 1;
                ty = semantic.pointer.child;
            }
        }
        ty = switch (projection) {
            .field => |index| blk: {
                const range = types.fields(graph, ty) orelse return null;
                if (index >= range.len) return null;
                break :blk graph.fields.items[range.start + index].ty;
            },
            .variant => |index| blk: {
                const range = types.variants(graph, ty) orelse return null;
                if (index >= range.len) return null;
                break :blk graph.variants.items[range.start + index].payload_type orelse return null;
            },
            .static_index, .dynamic_index => types.arrayElement(graph, ty) orelse return null,
            .dereference => blk: {
                const semantic = graph.resolvedSemanticType(ty) orelse return null;
                if (semantic != .pointer) return null;
                break :blk semantic.pointer.child;
            },
        };
    }
    return ty;
}

fn appendLeaves(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, path: facts.InputPath, leaves: *std.ArrayList(facts.InputPath), depth: usize) anyerror!void {
    if (depth > 128) return error.ExecutionTransferHasNoReceipt;
    if (types.isExecutionReceiptType(graph, ty)) {
        try leaves.append(allocator, path);
        return;
    }
    const semantic = graph.resolvedSemanticType(ty) orelse return error.ExecutionTransferHasNoReceipt;
    if (semantic == .pointer) return;
    if (types.arrayElement(graph, ty)) |element| {
        const length = types.arrayLength(graph, ty) orelse return error.ExecutionTransferHasNoReceipt;
        for (0..std.math.cast(usize, length) orelse return error.ExecutionTransferHasNoReceipt) |index| {
            const projections = try std.mem.concat(allocator, Projection, &.{ path.projections, &.{.{ .static_index = index }} });
            try appendLeaves(allocator, graph, element, .{ .input_index = path.input_index, .projections = projections }, leaves, depth + 1);
        }
    } else if (types.fields(graph, ty)) |fields| {
        for (0..fields.len) |index| {
            const projections = try std.mem.concat(allocator, Projection, &.{ path.projections, &.{.{ .field = @intCast(index) }} });
            try appendLeaves(allocator, graph, graph.fields.items[fields.start + index].ty, .{ .input_index = path.input_index, .projections = projections }, leaves, depth + 1);
        }
    } else if (types.variants(graph, ty)) |variants| {
        for (0..variants.len) |index| {
            const payload = graph.variants.items[variants.start + index].payload_type orelse continue;
            const projections = try std.mem.concat(allocator, Projection, &.{ path.projections, &.{.{ .variant = @intCast(index) }} });
            try appendLeaves(allocator, graph, payload, .{ .input_index = path.input_index, .projections = projections }, leaves, depth + 1);
        }
    }
}

fn normalizeOutput(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.Function, output: contracts.Output) anyerror!contracts.Output {
    var result = output;
    var leaves: std.ArrayList(facts.InputPath) = .empty;
    for (output.execution_transfers) |path| {
        const before = leaves.items.len;
        const ty = selectedType(graph, function, path, false) orelse return error.ExecutionTransferHasNoReceipt;
        try appendLeaves(allocator, graph, ty, path, &leaves, 0);
        if (leaves.items.len == before) return error.ExecutionTransferHasNoReceipt;
    }
    result.execution_transfers = try leaves.toOwnedSlice(allocator);
    result.dependencies = try std.mem.concat(allocator, facts.InputPath, &.{ output.dependencies, result.execution_transfers });
    result.ownership_transfers = try std.mem.concat(allocator, facts.InputPath, &.{ output.ownership_transfers, result.execution_transfers });
    const outcomes = try allocator.dupe(contracts.Output.Outcome, output.outcomes);
    for (outcomes) |*outcome| {
        const value = try allocator.create(contracts.Output);
        value.* = try normalizeOutput(allocator, graph, function, outcome.value.*);
        outcome.value = value;
    }
    result.outcomes = outcomes;
    return result;
}

pub fn normalize(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.Function, contract: contracts.Contract) anyerror!contracts.Contract {
    var result = contract;
    var completed: std.ArrayList(facts.InputPath) = .empty;
    for (contract.completed_executions) |path| {
        const before = completed.items.len;
        const ty = selectedType(graph, function, path, true) orelse return error.ExecutionTransferHasNoReceipt;
        try appendLeaves(allocator, graph, ty, path, &completed, 0);
        if (completed.items.len == before) return error.ExecutionTransferHasNoReceipt;
    }
    result.completed_executions = try completed.toOwnedSlice(allocator);
    const outputs = try allocator.dupe(contracts.Output, contract.outputs);
    for (outputs) |*output| output.* = try normalizeOutput(allocator, graph, function, output.*);
    result.outputs = outputs;
    const outcomes = try allocator.dupe(contracts.Contract.Outcome, contract.outcomes);
    for (outcomes) |*outcome| {
        const effects = try allocator.create(contracts.Contract);
        effects.* = try normalize(allocator, graph, function, outcome.effects.*);
        outcome.effects = effects;
    }
    result.outcomes = outcomes;
    const guards = try allocator.dupe(contracts.Contract.Guarded, contract.guarded_effects);
    for (guards) |*guard| {
        const effects = try allocator.create(contracts.Contract);
        effects.* = try normalize(allocator, graph, function, guard.effects.*);
        guard.effects = effects;
    }
    result.guarded_effects = guards;
    return result;
}

fn canContainReceipt(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, depth: usize) bool {
    if (depth > 128) return true;
    if (types.isExecutionReceiptType(graph, ty)) return true;
    const semantic = graph.resolvedSemanticType(ty) orelse return true;
    if (semantic == .pointer) return canContainReceipt(graph, semantic.pointer.child, depth + 1);
    if (types.arrayElement(graph, ty)) |element| return canContainReceipt(graph, element, depth + 1);
    if (types.fields(graph, ty)) |fields| {
        for (graph.fields.items[fields.start..][0..fields.len]) |field| if (canContainReceipt(graph, field.ty, depth + 1)) return true;
    }
    if (types.variants(graph, ty)) |variants| {
        for (graph.variants.items[variants.start..][0..variants.len]) |variant| if (variant.payload_type) |payload| {
            if (canContainReceipt(graph, payload, depth + 1)) return true;
        };
    }
    return false;
}

pub fn usesExecutionReceipts(graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.Function) bool {
    for (graph.fields.items[function.input.start..][0..function.input.len]) |field| {
        const semantic = graph.resolvedSemanticType(field.ty) orelse continue;
        const ty = if (semantic == .pointer) semantic.pointer.child else field.ty;
        if (canContainReceipt(graph, ty, 0)) return true;
    }
    for (graph.fields.items[function.output.start..][0..function.output.len]) |field|
        if (canContainReceipt(graph, field.ty, 0)) return true;
    return false;
}

fn filterEffect(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.Function, effect: facts.ValueEffect) anyerror!facts.ValueEffect {
    var result = effect;
    var paths: std.ArrayList(facts.InputPath) = .empty;
    for (effect.input_execution_receipts) |path| {
        const ty = selectedType(graph, function, path, true);
        if (ty == null or canContainReceipt(graph, ty.?, 0)) try paths.append(allocator, path);
    }
    result.input_execution_receipts = try paths.toOwnedSlice(allocator);
    const fields = try allocator.dupe(facts.OutputFieldEffect, effect.fields);
    for (fields) |*field| {
        const value = try allocator.create(facts.ValueEffect);
        value.* = try filterEffect(allocator, graph, function, field.value.*);
        field.value = value;
    }
    result.fields = fields;
    const variants = try allocator.dupe(facts.OutputVariantEffect, effect.variants);
    for (variants) |*variant| {
        const value = try allocator.create(facts.ValueEffect);
        value.* = try filterEffect(allocator, graph, function, variant.value.*);
        variant.value = value;
    }
    result.variants = variants;
    const domains = try allocator.dupe(facts.OutputDomainEffect, effect.domain_values);
    for (domains) |*domain| {
        const value = try allocator.create(facts.ValueEffect);
        value.* = try filterEffect(allocator, graph, function, domain.value.*);
        domain.value = value;
        if (domain.required_reads) |reads| {
            const filtered = try allocator.create(facts.ValueEffect);
            filtered.* = try filterEffect(allocator, graph, function, reads.*);
            domain.required_reads = filtered;
        }
    }
    result.domain_values = domains;
    const executions = try allocator.dupe(facts.FreshExecution, effect.fresh_executions);
    for (executions) |*execution| {
        const value = try allocator.create(facts.ValueEffect);
        value.* = try filterEffect(allocator, graph, function, execution.inputs.*);
        execution.inputs = value;
    }
    result.fresh_executions = executions;
    return result;
}

fn filterPosts(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.Function, posts: []const facts.PlacePostState) ![]const facts.PlacePostState {
    const result = try allocator.dupe(facts.PlacePostState, posts);
    for (result) |*post| post.value = try filterEffect(allocator, graph, function, post.value);
    return result;
}

pub fn filteredSummary(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.Function, summary: facts.SafetySummary) anyerror!facts.SafetySummary {
    var result = summary;
    const outputs = try allocator.dupe(facts.ValueEffect, summary.outputs);
    for (outputs) |*output| output.* = try filterEffect(allocator, graph, function, output.*);
    result.outputs = outputs;
    result.input_post_states = try filterPosts(allocator, graph, function, summary.input_post_states);
    const outcomes = try allocator.dupe(facts.OutcomePostStates, summary.outcome_post_states);
    for (outcomes) |*outcome| outcome.input_post_states = try filterPosts(allocator, graph, function, outcome.input_post_states);
    result.outcome_post_states = outcomes;
    const guards = try allocator.dupe(facts.GuardedSafetyEffects, summary.guarded_effects);
    for (guards) |*guard| {
        const effects = try allocator.create(facts.SafetySummary);
        effects.* = try filteredSummary(allocator, graph, function, guard.effects.*);
        guard.effects = effects;
    }
    result.guarded_effects = guards;
    const opaque_effects = try allocator.dupe(facts.OpaqueStorageEffect, summary.opaque_storage_effects);
    for (opaque_effects) |*entry| entry.hidden_dependencies = try filterEffect(allocator, graph, function, entry.hidden_dependencies);
    result.opaque_storage_effects = opaque_effects;
    return result;
}

fn pathsOverlap(a: facts.InputPath, b: facts.InputPath) bool {
    if (a.input_index != b.input_index or a.storage_domain != b.storage_domain) return false;
    const count = @min(a.projections.len, b.projections.len);
    for (a.projections[0..count], b.projections[0..count]) |left, right| if (!left.eql(right)) return false;
    return true;
}

fn checkEffectOrigins(allowed: contracts.Output, actual: facts.ValueEffect, output_index: u32) ?contracts.Failure {
    for (actual.input_execution_receipts) |path| {
        var permitted = false;
        for (allowed.execution_transfers) |candidate| if (pathsOverlap(path, candidate)) {
            permitted = true;
            break;
        };
        if (!permitted) return .{ .kind = .missing_execution_transfer, .output_index = output_index, .input = path };
    }
    if (actual.fresh_executions.len != 0) return .{ .kind = .missing_execution_transfer, .output_index = output_index };
    for (actual.fields) |field| if (checkEffectOrigins(allowed, field.value.*, output_index)) |failure| return failure;
    for (actual.domain_values) |domain| {
        if (checkEffectOrigins(allowed, domain.value.*, output_index)) |failure| return failure;
        if (domain.required_reads) |reads| if (checkEffectOrigins(allowed, reads.*, output_index)) |failure| return failure;
    }
    for (actual.variants) |variant| {
        var selected = allowed;
        for (allowed.outcomes) |outcome| if (outcome.variant_index == variant.index) {
            selected = outcome.value.*;
            break;
        };
        if (checkEffectOrigins(selected, variant.value.*, output_index)) |failure| return failure;
    }
    return null;
}

pub fn checkOrigins(contract: contracts.Contract, summary: facts.SafetySummary) ?contracts.Failure {
    for (summary.outputs, 0..) |output, index| {
        if (index >= contract.outputs.len) break;
        if (checkEffectOrigins(contract.outputs[index], output, @intCast(index))) |failure| return failure;
    }
    for (summary.guarded_effects) |guard| {
        // Guarded permissions are checked against the matching conditional
        // contract when available; otherwise retain the common contract.
        var allowed = contract;
        for (contract.guarded_effects) |candidate| if (candidate.conditions.eql(guard.conditions)) {
            allowed = candidate.effects.*;
            break;
        };
        if (checkOrigins(allowed, guard.effects.*)) |failure| return failure;
    }
    return null;
}
