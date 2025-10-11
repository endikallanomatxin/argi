const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const sg = @import("semantic_graph.zig");
const sem = @import("semantizer.zig");
const sgp = @import("semantic_graph_print.zig");
const diagnostic = @import("../1_base/diagnostic.zig");

const abs = @import("abstracts.zig");
const gen = @import("generics.zig");

pub const Scope = struct {
    parent: ?*Scope,
    allocator: *const std.mem.Allocator,

    nodes: std.ArrayList(*sg.SGNode),
    bindings: std.StringHashMap(*sg.BindingDeclaration),
    functions: std.StringHashMap(std.ArrayList(*sg.FunctionDeclaration)),
    types: std.StringHashMap(*sg.TypeDeclaration),
    abstracts: std.StringHashMap(*abs.AbstractInfo),
    abstract_impls: std.StringHashMap(std.ArrayList(abs.AbstractImplEntry)),
    abstract_defaults: std.StringHashMap(abs.AbstractDefaultEntry),
    generic_functions: std.StringHashMap(std.ArrayList(gen.GenericTemplate)),
    generic_types: std.StringHashMap(std.ArrayList(gen.GenericTypeTemplate)),
    deferred: std.ArrayList(sem.DeferredGroup),

    current_fn: ?*sg.FunctionDeclaration,

    pub fn init(
        a: *const std.mem.Allocator,
        p: ?*Scope,
        fnc: ?*sg.FunctionDeclaration,
    ) !Scope {
        return .{
            .parent = p,
            .allocator = a,
            .nodes = std.ArrayList(*sg.SGNode).init(a.*),
            .bindings = std.StringHashMap(*sg.BindingDeclaration).init(a.*),
            .functions = std.StringHashMap(std.ArrayList(*sg.FunctionDeclaration)).init(a.*),
            .types = std.StringHashMap(*sg.TypeDeclaration).init(a.*),
            .abstracts = std.StringHashMap(*abs.AbstractInfo).init(a.*),
            .abstract_impls = std.StringHashMap(std.ArrayList(abs.AbstractImplEntry)).init(a.*),
            .abstract_defaults = std.StringHashMap(abs.AbstractDefaultEntry).init(a.*),
            .generic_functions = std.StringHashMap(std.ArrayList(gen.GenericTemplate)).init(a.*),
            .generic_types = std.StringHashMap(std.ArrayList(gen.GenericTypeTemplate)).init(a.*),
            .deferred = std.ArrayList(sem.DeferredGroup).init(a.*),
            .current_fn = fnc,
        };
    }

    pub fn lookupBinding(self: *Scope, n: []const u8) ?*sg.BindingDeclaration {
        if (self.bindings.get(n)) |b| return b;
        if (self.parent) |p| return p.lookupBinding(n);
        return null;
    }

    // Deprecated: use resolveOverload in Semantizer instead.
    pub fn lookupFunction(self: *Scope, n: []const u8) ?*sg.FunctionDeclaration {
        if (self.functions.getPtr(n)) |lst| {
            if (lst.items.len > 0) return lst.items[0];
        }
        if (self.parent) |p| return p.lookupFunction(n);
        return null;
    }

    pub fn lookupType(self: *Scope, n: []const u8) ?*sg.TypeDeclaration {
        if (self.types.get(n)) |t| return t;
        if (self.parent) |p| return p.lookupType(n);
        return null;
    }
};
