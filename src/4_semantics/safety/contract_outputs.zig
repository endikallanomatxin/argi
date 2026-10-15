const std = @import("std");
const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const facts = @import("facts.zig");
const contracts = @import("contracts.zig");

/// Build published output facts from the fixed signature. A concrete body is
/// never consulted here. Ownership roots are roles rebased at each call, and
/// validity permissions never manufacture acquisition receipts or addresses.
pub fn build(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, allowed: contracts.Output, source: usize) !facts.ValueEffect {
    var builder = Builder{ .allocator = allocator, .graph = graph, .next_source = source };
    return builder.value(ty, allowed, 0);
}

const Builder = struct {
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,
    next_source: usize,

    fn value(self: *Builder, ty: graph_mod.GlobalTypeId, allowed: contracts.Output, depth: usize) anyerror!facts.ValueEffect {
        if (depth > 64) return error.ContractOutputShapeTooDeep;
        var dependencies: std.ArrayList(facts.InputDependency) = .empty;
        for (allowed.dependencies) |path| try dependencies.append(self.allocator, .{ .path = path, .validity_only = true });
        for (allowed.ownership_transfers) |path| try dependencies.append(self.allocator, .{ .path = path, .transfers_ownership = true });
        if (allowed.referent) |referent| {
            for (dependencies.items) |*dependency| if (dependency.path.input_index == referent.input_index and dependency.path.projections.len == referent.projections.len) {
                dependency.validity_only = false;
            };
        }
        var result = facts.ValueEffect{
            .input_dependencies = try dependencies.toOwnedSlice(self.allocator),
            .input_domains = allowed.domains,
            .opaque_storage_dependencies = allowed.storage_sources,
            .explicit_dependency = allowed.dependencies.len != 0 or allowed.domains.len != 0,
        };
        if (allowed.ownership_transfers.len != 0) return result;
        const semantic = self.graph.semanticType(ty);
        if (semantic == .pointer or semantic == .virtual or semantic == .builtin) return result;
        if (types.variants(self.graph, ty)) |range| {
            const variants = try self.allocator.alloc(facts.OutputVariantEffect, range.len);
            for (self.graph.variants.items[range.start..][0..range.len], variants, 0..) |variant, *output, index| {
                const child = try self.allocator.create(facts.ValueEffect);
                var child_allowed = allowed;
                child_allowed.outcomes = &.{};
                for (allowed.outcomes) |outcome| if (outcome.variant_index == index) {
                    child_allowed = outcome.value.*;
                    break;
                };
                child.* = if (variant.payload_type) |payload| try self.value(payload, child_allowed, depth + 1) else .{};
                output.* = .{ .index = @intCast(index), .value = child };
            }
            result.variants = variants;
            return result;
        }
        if (allowed.fresh_owner and types.hasDestructor(self.graph, ty)) {
            result.fresh_cleanup_obligation = true;
            const source = self.next_source;
            self.next_source +%= 1;
            const roots = try self.allocator.alloc(facts.FreshEffectSource, 1);
            roots[0] = source;
            result.fresh_owned_roots = roots;
            result.fresh_dependencies = roots;
        }
        if (types.fields(self.graph, ty)) |range| {
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, range.len);
            for (self.graph.fields.items[range.start..][0..range.len], fields, 0..) |field, *output, index| {
                const child = try self.allocator.create(facts.ValueEffect);
                child.* = try self.value(field.ty, allowed, depth + 1);
                output.* = .{ .index = @intCast(index), .value = child };
            }
            result.fields = fields;
        } else if (types.arrayElement(self.graph, ty)) |element| {
            const length = types.arrayLength(self.graph, ty) orelse return error.InvalidContractArray;
            const fields = try self.allocator.alloc(facts.OutputFieldEffect, @intCast(length));
            for (fields, 0..) |*field, index| {
                const child = try self.allocator.create(facts.ValueEffect);
                child.* = try self.value(element, allowed, depth + 1);
                field.* = .{ .index = @intCast(index), .value = child };
            }
            result.fields = fields;
        }
        return result;
    }
};
