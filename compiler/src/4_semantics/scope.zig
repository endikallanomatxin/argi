const std = @import("std");
const sg = @import("semantic_graph.zig");

const abs = @import("abstracts.zig");
const gen = @import("generics.zig");
const typ = @import("types.zig");

pub const DeferredGroup = struct {
    nodes: []const *sg.SGNode,
};

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
    deferred: std.ArrayList(DeferredGroup),

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
            .deferred = std.ArrayList(DeferredGroup).init(a.*),
            .current_fn = fnc,
        };
    }

    pub fn lookupBinding(self: *Scope, n: []const u8) ?*sg.BindingDeclaration {
        if (self.bindings.get(n)) |b| return b;
        if (self.parent) |p| return p.lookupBinding(n);
        return null;
    }

    pub fn lookupType(self: *Scope, n: []const u8) ?*sg.TypeDeclaration {
        if (self.types.get(n)) |t| return t;
        if (self.parent) |p| return p.lookupType(n);
        return null;
    }

    pub fn lookupGenericTypeTemplate(
        self: *Scope,
        name: []const u8,
        param_count: usize,
    ) ?*const gen.GenericTypeTemplate {
        var cur: ?*Scope = self;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_types.get(name)) |list_ptr| {
                for (list_ptr.items, 0..) |tmpl, idx| {
                    if (tmpl.param_names.len == param_count) return &list_ptr.items[idx];
                }
            }
        }
        return null;
    }

    pub fn lookupAbstractDefault(s: *Scope, name: []const u8) ?abs.AbstractDefaultEntry {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.abstract_defaults.get(name)) |def| return def;
        }
        return null;
    }

    pub fn lookupAbstractInfo(s: *Scope, name: []const u8) ?*abs.AbstractInfo {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.abstracts.get(name)) |info| return info;
        }
        return null;
    }

    pub fn findDeinit(s: *Scope, ty: sg.Type) ?*sg.FunctionDeclaration {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr("deinit")) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (cand.input.fields.len == 0) continue;
                    const first = cand.input.fields[0];
                    if (first.ty != .pointer_type) continue;
                    const ptr_info = first.ty.pointer_type.*;
                    if (ptr_info.mutability != .read_write) continue;
                    const pointee = ptr_info.child.*;
                    if (typ.typesExactlyEqual(pointee, ty)) return cand;
                }
            }
        }
        return null;
    }
};
