const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const sg = @import("semantic_graph.zig");

pub const GenericDispatchKind = enum {
    regular,
    abstract_contract,
};

pub const GenericParamKind = enum {
    type,
    comptime_int,
};

pub const GenericParam = struct {
    name: []const u8,
    kind: GenericParamKind,
    value_type: ?sg.Type = null,
};

pub const GenericArgValue = union(enum) {
    type: sg.Type,
    comptime_int: i64,
};

pub const GenericValueBinding = struct {
    ty: sg.Type,
    value: GenericArgValue,
};

// Generic function template used for monomorphization
pub const GenericTemplate = struct {
    name: []const u8,
    location: tok.Location,
    params: []const GenericParam,
    param_abstract_constraints: []const ?[]const u8,
    dispatch_kind: GenericDispatchKind = .regular,
    input: syn.StructTypeLiteral,
    output: syn.StructTypeLiteral,
    body: ?*syn.STNode,
};

// Generic type template for monomorphization of named struct types
pub const GenericTypeTemplate = struct {
    name: []const u8,
    location: tok.Location,
    params: []const GenericParam,
    body: *syn.STNode,
};
