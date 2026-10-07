const std = @import("std");
const facts = @import("safety_facts.zig");

pub const DomainId = enum(u32) { _ };

/// One abstract domain may cover several concrete storage paths. Mappings are
/// implementation metadata, not a new runtime owner or retained lifetime.
pub const Mapping = struct {
    domain: DomainId,
    paths: []const facts.InputPath,
};

/// Captured generation identities, instantiated at a concrete conversion.
/// These are dependency anchors, never owned roots or fresh acquisitions.
pub const Captured = struct {
    domain: DomainId,
    generations: []const facts.ValidityRootId,
};

pub const InvalidCapture = enum { duplicate_domain, empty_domain, aliased_domains };

pub fn validateCaptured(domains: []const Captured) ?InvalidCapture {
    for (domains, 0..) |domain, index| {
        if (domain.generations.len == 0) return .empty_domain;
        for (domains[0..index]) |previous| {
            if (previous.domain == domain.domain) return .duplicate_domain;
            for (domain.generations) |root| {
                for (previous.generations) |other| if (root == other) return .aliased_domains;
            }
        }
    }
    return null;
}

pub const InvalidMapping = enum {
    duplicate_domain,
    empty_domain,
    wrong_receiver,
    receiver_slot,
    overlapping_domains,
};

/// Structurally disjoint domains prevent ancestor paths from invalidating a
/// sibling mapping. Paths within the same domain may overlap intentionally.
/// Unknown/dynamic indices conservatively overlap all indices at that depth.
/// Type-aware lowering still verifies that every projection is legal before
/// publishing a mapping. Distinct reference fields can still point at the same
/// physical generation: conversion must check actual roots separately. This
/// routine checks symbolic relationships only and is not an aliasing proof.
pub fn validate(mappings: []const Mapping, receiver_index: u32) ?InvalidMapping {
    for (mappings, 0..) |mapping, index| {
        if (mapping.paths.len == 0) return .empty_domain;
        for (mappings[0..index]) |previous| if (previous.domain == mapping.domain) return .duplicate_domain;
        for (mapping.paths) |path| {
            if (path.input_index != receiver_index) return .wrong_receiver;
            if (path.projections.len == 0) return .receiver_slot;
            for (mappings[0..index]) |previous| {
                for (previous.paths) |other| if (overlaps(path, other)) return .overlapping_domains;
            }
        }
    }
    return null;
}

pub fn pathsFor(mappings: []const Mapping, domain: DomainId) ?[]const facts.InputPath {
    for (mappings) |mapping| if (mapping.domain == domain) return mapping.paths;
    return null;
}

fn overlaps(a: facts.InputPath, b: facts.InputPath) bool {
    if (a.input_index != b.input_index) return false;
    const shared = @min(a.projections.len, b.projections.len);
    for (a.projections[0..shared], b.projections[0..shared]) |x, y| {
        if (x == .dynamic_index and (y == .dynamic_index or y == .static_index)) continue;
        if (y == .dynamic_index and x == .static_index) continue;
        if (!x.eql(y)) return false;
    }
    return true;
}

test "safety domains preserve private path groups and disjoint identities" {
    const first = [_]facts.InputPath{.{ .input_index = 2, .projections = &.{.{ .field = 0 }} }};
    const second = [_]facts.InputPath{
        .{ .input_index = 2, .projections = &.{.{ .field = 1 }} },
        .{ .input_index = 2, .projections = &.{.{ .field = 2 }} },
    };
    const mappings = [_]Mapping{
        .{ .domain = @enumFromInt(0), .paths = &first },
        .{ .domain = @enumFromInt(1), .paths = &second },
    };
    try std.testing.expect(validate(&mappings, 2) == null);
    try std.testing.expectEqual(@as(usize, 2), pathsFor(&mappings, @enumFromInt(1)).?.len);
    try std.testing.expect(pathsFor(&mappings, @enumFromInt(9)) == null);
}

test "safety domains reject ancestor and dynamic index aliases" {
    const ancestor = facts.InputPath{ .input_index = 0, .projections = &.{.{ .field = 1 }} };
    const child = facts.InputPath{ .input_index = 0, .projections = &.{ .{ .field = 1 }, .{ .static_index = 3 } } };
    const unknown = facts.InputPath{ .input_index = 0, .projections = &.{ .{ .field = 1 }, .dynamic_index } };
    for ([_]facts.InputPath{ ancestor, unknown }) |other| {
        try std.testing.expectEqual(.overlapping_domains, validate(&.{
            .{ .domain = @enumFromInt(0), .paths = &.{child} },
            .{ .domain = @enumFromInt(1), .paths = &.{other} },
        }, 0).?);
    }
}

test "safety domains reject empty duplicate and unrelated mappings" {
    const path = facts.InputPath{ .input_index = 0, .projections = &.{.{ .field = 1 }} };
    try std.testing.expectEqual(.empty_domain, validate(&.{.{ .domain = @enumFromInt(0), .paths = &.{} }}, 0).?);
    try std.testing.expectEqual(.wrong_receiver, validate(&.{.{ .domain = @enumFromInt(0), .paths = &.{path} }}, 1).?);
    try std.testing.expectEqual(.receiver_slot, validate(&.{.{ .domain = @enumFromInt(0), .paths = &.{.{ .input_index = 0 }} }}, 0).?);
    try std.testing.expectEqual(.duplicate_domain, validate(&.{
        .{ .domain = @enumFromInt(0), .paths = &.{path} },
        .{ .domain = @enumFromInt(0), .paths = &.{path} },
    }, 0).?);
}

test "safety domains reject aliases hidden behind distinct reference fields" {
    const a: facts.ValidityRootId = @enumFromInt(3);
    const b: facts.ValidityRootId = @enumFromInt(9);
    const c: facts.ValidityRootId = @enumFromInt(11);
    try std.testing.expect(validateCaptured(&.{
        .{ .domain = @enumFromInt(0), .generations = &.{ a, b } },
        .{ .domain = @enumFromInt(1), .generations = &.{c} },
    }) == null);
    try std.testing.expectEqual(.aliased_domains, validateCaptured(&.{
        .{ .domain = @enumFromInt(0), .generations = &.{ a, b } },
        .{ .domain = @enumFromInt(1), .generations = &.{ c, b } },
    }).?);
    // Aliases within one domain share an invalidation obligation and are valid.
    try std.testing.expect(validateCaptured(&.{.{ .domain = @enumFromInt(0), .generations = &.{ a, a } }}) == null);
    try std.testing.expectEqual(.empty_domain, validateCaptured(&.{.{ .domain = @enumFromInt(0), .generations = &.{} }}).?);
    try std.testing.expectEqual(.duplicate_domain, validateCaptured(&.{
        .{ .domain = @enumFromInt(0), .generations = &.{a} },
        .{ .domain = @enumFromInt(0), .generations = &.{b} },
    }).?);
}
