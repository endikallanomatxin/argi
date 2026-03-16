const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");

pub const GenericDispatchKind = enum {
    regular,
    abstract_contract,
};

// Generic function template used for monomorphization
pub const GenericTemplate = struct {
    name: []const u8,
    location: tok.Location,
    param_names: []const []const u8,
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
    param_names: []const []const u8,
    body: *syn.STNode,
};
